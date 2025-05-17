# v7_insert_into_fdx_ebill_prod.py
# Stable production version for inserting FDX transformed blobs into fdx_ebill_prod with function wrappers

import os
import pandas as pd
import pyodbc
from dotenv import load_dotenv
from azure.storage.blob import BlobServiceClient
from io import BytesIO

# === Load ENV ===
def load_environment():
    load_dotenv()

# === Azure Blob Connection ===
def get_blob_container():
    account_name = os.getenv("AZURE_STORAGE_ACCOUNT")
    account_key = os.getenv("AZURE_STORAGE_KEY")
    container_name = os.getenv("AZURE_TRANSFORMED_CONTAINER")
    blob_service_client = BlobServiceClient(
        account_url=f"https://{account_name}.blob.core.windows.net",
        credential=account_key
    )
    return blob_service_client.get_container_client(container_name)

# === SQL Connection ===
def get_sql_connection():
    conn_str = (
        f"DRIVER={{{os.getenv('SQL_DRIVER', 'ODBC Driver 17 for SQL Server')}}};"
        f"SERVER={os.getenv('SQL_SERVER')};"
        f"DATABASE={os.getenv('SQL_DATABASE')};"
        f"UID={os.getenv('SQL_USERNAME')};"
        f"PWD={os.getenv('SQL_PASSWORD')}"
    )
    conn = pyodbc.connect(conn_str)
    cursor = conn.cursor()
    cursor.fast_executemany = True
    return conn, cursor

# === Constants ===
FDX_TABLE = "TestDB.dbo.fdx_ebill_prod"
CONTROL_TABLE = "TestDB.dbo.control_master"

fdx_cols = [
    "controlno", "childid", "trackingnumber", "accountnumber", "invoicenumber", "invoicedate",
    "shipdate", "zone", "servicetypecode", "servicetypedescription", "packagecode", "groundservicecode",
    "weightunit", "billedweight", "pieces", "payortype", "shipperstate", "shippercountry",
    "recipientstate", "recipientcountry", "currency", "chargecategory", "chargedescription",
    "chargeamount", "bundleno", "freightamt", "voldiscamt", "earneddiscamt", "autodiscamt",
    "perfpriceamt", "billeddiscountpct", "billeddiscountamt", "billednetfreightcharge", "loadtimestamp"
]

insert_fdx_sql = f"""
    INSERT INTO {FDX_TABLE} (
        ControlNo, ChildID, TrackingNumber, AccountNumber, InvoiceNumber, InvoiceDate,
        ShipDate, Zone, ServiceTypeCode, ServiceTypeDescription, PackageCode, GroundServiceCode,
        WeightUnit, BilledWeight, Pieces, PayorType, ShipperState, ShipperCountry,
        RecipientState, RecipientCountry, Currency, ChargeCategory, ChargeDescription,
        ChargeAmount, BundleNo, FreightAmt, VolDiscAmt, EarnedDiscAmt, AutoDiscAmt,
        PerfPriceAmt, BilledDiscountPct, BilledDiscountAmt, BilledNetFreightCharge,
        LoadTimestamp
    ) VALUES (
        ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
    )
"""

# === Insert FDX Records ===
def insert_fdx_records(df, cursor, blob_name):
    cursor.executemany(insert_fdx_sql, df.values.tolist())
    cursor.connection.commit()
    print(f"✅ Inserted {len(df)} rows into fdx_ebill_prod from {blob_name}")

# === Process a FedEx File ===
def process_fdx_blob(df, blob_name, cursor):
    df = df.copy()
    df.columns = df.columns.str.strip().str.lower()
    df = df.rename(columns={"clientid": "childid"})

    required_cols = {"controlno", "childid", "carrier"}
    if not required_cols.issubset(set(df.columns)):
        print(f"⚠️ Skipping {blob_name} — missing ControlNo, ChildID, or carrier column")
        print(f"🔍 Detected columns: {df.columns.tolist()}")
        return

    carrier = df["carrier"].iloc[0].strip().upper()
    childid = int(df["childid"].iloc[0])
    controlno = int(df["controlno"].iloc[0])

    if carrier != "FDX" or childid not in (11816, 11817):
        print(f"⚠️ Skipping {blob_name}: not a FedEx file (Carrier: {carrier}, ChildID: {childid})")
        return

    cursor.execute(f"SELECT 1 FROM {FDX_TABLE} WHERE ControlNo = ?", (int(controlno),))
    if cursor.fetchone():
        print(f"⚠️ Skipped {blob_name}: ControlNo {controlno} already exists.")
        return

    df = df.drop(columns=["carrier"])

    float_cols = [
        "billedweight", "chargeamount", "freightamt", "voldiscamt",
        "earneddiscamt", "autodiscamt", "perfpriceamt",
        "billeddiscountpct", "billeddiscountamt", "billednetfreightcharge"
    ]

    for col in float_cols:
        df[col] = (
            df[col]
            .astype(str)
            .str.replace(r"[^0-9.\-]", "", regex=True)
            .replace("", "0")
            .astype(float)
            .round(4)
        )

    df = df[fdx_cols]
    insert_fdx_records(df, cursor, blob_name)

# === Process a Single Blob ===
def process_blob(blob, container_client, cursor):
    if not blob.name.endswith(".csv"):
        return

    if any(prefix in blob.name.lower() for prefix in ["clienta", "clientb", "clientc"]):
        return

    cursor.execute(f"SELECT 1 FROM {CONTROL_TABLE} WHERE FileName = ?", (blob.name,))
    if cursor.fetchone():
        print(f"⚠️ Skipped {blob.name}: already processed.")
        return

    print(f"\n📥 Downloading blob: {blob.name}")
    blob_data = container_client.get_blob_client(blob.name).download_blob().readall()
    df = pd.read_csv(BytesIO(blob_data))
    process_fdx_blob(df, blob.name, cursor)

# === Main Execution ===
def main():
    print("\n🔍 Starting FDX V7 ingestion...")
    load_environment()
    container_client = get_blob_container()
    conn, cursor = get_sql_connection()

    for blob in container_client.list_blobs():
        process_blob(blob, container_client, cursor)

    cursor.close()
    conn.close()
    print("\n✅ FDX V7 ingestion complete.")

if __name__ == "__main__":
    main()
