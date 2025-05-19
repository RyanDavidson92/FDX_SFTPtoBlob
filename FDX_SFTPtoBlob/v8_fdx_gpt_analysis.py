import os
import pyodbc
import pandas as pd
from openai import OpenAI
from datetime import datetime
import warnings
from dotenv import load_dotenv
load_dotenv()


warnings.filterwarnings("ignore", message="pandas only supports SQLAlchemy")

# ✅ Initialize OpenAI client
client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))

# ✅ SQL connection
conn = pyodbc.connect(
    f"DRIVER={os.getenv('SQL_DRIVER')};"
    f"SERVER={os.getenv('SQL_SERVER')};"
    f"DATABASE={os.getenv('SQL_DATABASE')};"
    f"UID={os.getenv('SQL_USERNAME')};"
    f"PWD={os.getenv('SQL_PASSWORD')}"
)
cursor = conn.cursor()


# ✅ Define ControlNo to process
control_no = 1009

# ✅ Early exit if summary already exists
summary_check_query = "SELECT 1 FROM gpt_fdx_summary_analysis WHERE ControlNo = ?"
cursor.execute(summary_check_query, (control_no,))
if cursor.fetchone():
    print(f"⛔️ ControlNo {control_no} has already been analyzed. Skipping GPT processing.")
    exit()

# ✅ Get FedEx audit rows missing AnalysisText and with nonzero PotentialError
audit_query = """
SELECT ID, ServiceTypeCode, ServiceTypeDescription, Zone, BilledWeight,
       BilledNetFreightCharge, Contract_Rate, PotentialError, HashKey
FROM fdx_base_rate_audit_sanitized
WHERE ControlNo = ? AND AnalysisText IS NULL AND ABS(PotentialError) > 0.01
"""
audit_df = pd.read_sql(audit_query, conn, params=[control_no])

# ✅ Row-level GPT analysis with rate context (RAG-style)
for _, row in audit_df.iterrows():
    context_query = """
    SELECT TOP 10 *
    FROM fdx_rate_master
    WHERE ServiceTypeCode = ?
      AND Zone = ?
      AND MinWeight <= ? AND MaxWeight >= ?
    ORDER BY ABS(Rate - ?) ASC
    """
    context_df = pd.read_sql(context_query, conn, params=[
        row.ServiceTypeCode, row.Zone, row.BilledWeight, row.BilledWeight, row.BilledNetFreightCharge
    ])

    context_text = context_df.to_string(index=False)

    prompt = f"""
You are a parcel audit AI. A FedEx shipment was charged ${row.BilledNetFreightCharge:.2f} but your expected rate was ${row.Contract_Rate:.2f}, creating a potential error of ${row.PotentialError:.2f}.

Here is the applicable rate context from the fdx_rate_master table:

{context_text}

Explain whether the discrepancy is likely due to zone misalignment, weight band mismatch, or servicetype/rate misapplication .Be specific.
"""

    try:
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[{"role": "user", "content": prompt}],
            temperature=0.3
        )
        analysis_text = response.choices[0].message.content

        # ✅ Save result
        update_query = """
        UPDATE fdx_base_rate_audit_sanitized
        SET AnalysisText = ?
        WHERE HashKey = ?
        """
        cursor.execute(update_query, (analysis_text, row.HashKey))
        conn.commit()

    except Exception as e:
        print(f"❌ Error for row {row.HashKey}: {e}")





# ✅ Prepare input sample for summary
summary_rows = audit_df[[
    "ServiceTypeDescription", "Zone", "BilledWeight", "PotentialError"
]].to_string(index=False)

summary_prompt = f"""
You are a FedEx parcel audit assistant. Here are the rows that triggered errors for ControlNo {control_no}:

{summary_rows}

Based on this data, summarize where the errors most frequently occur. 
Look for patterns like common zones, weight ranges, or service types.
Respond in concise bullet points.
"""

try:
    summary_response = client.chat.completions.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": summary_prompt}],
        temperature=0.3
    )
    summary_text = summary_response.choices[0].message.content

    cursor.execute(
    "INSERT INTO gpt_fdx_summary_analysis (ControlNo, AnalysisText, Timestamp) VALUES (?, ?, GETDATE())",
    (control_no, summary_text)
)
    conn.commit()
    print(f"✅ FedEx V8 GPT audit complete for ControlNo {control_no}")

except Exception as e:
    print(f"❌ Summary generation failed: {e}")