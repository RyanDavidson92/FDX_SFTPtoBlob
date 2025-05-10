



CREATE OR ALTER PROCEDURE dbo.ups_base_rate_audit_master
    @ywControlno INT
AS
BEGIN
    SET NOCOUNT ON;

    -- 🔁 Prevent duplicate inserts by deleting existing audit rows for the control number
    DELETE FROM dbo.ups_base_rate_audit
    WHERE ControlNo = @ywControlno;

    DELETE FROM dbo.ups_base_rate_audit_unmatched
    WHERE ControlNo = @ywControlno;

    -- ✅ 1. Build CTE: Match UPS eBill rows to Rate Master
    ;WITH matched AS (
        SELECT DISTINCT
            e.[Lead Shipment Number],
            e.ControlNo,
            e.ChildID,
            e.BillToAccountNo,
            e.InvoiceDt,
            e.[Bill Option Code],
            e.[Container Type],
            e.[Transaction Date],
            e.[Package Quantity],
            e.[Sender Country],
            e.[Receiver Country],
            e.[Charge Category Code],
            e.[Charge Classification Code],
            e.[Charge Description],
            e.Zone,
            e.[Billed Weight],
            e.[Billed Weight Unit of Measure],
            e.[Net Amount],
            e.[Sender State],
            e.[Receiver State],
            e.[Invoice Currency Code],
            r.Rate,
            r.MinRate,
            ROW_NUMBER() OVER (
                PARTITION BY e.[Lead Shipment Number], e.ControlNo
                ORDER BY ABS(e.[Net Amount] -
                    CASE 
                        WHEN e.[Billed Weight] > 150 THEN r.Rate * e.[Billed Weight]
                        WHEN r.MinRate IS NOT NULL AND r.Rate < r.MinRate THEN r.MinRate * e.[Package Quantity]
                        ELSE r.Rate * e.[Package Quantity]
                    END
                ) ASC
            ) AS rn
        FROM dbo.ups_ebill_prod e
        LEFT JOIN dbo.ups_rate_master r
    ON TRY_CAST(e.Zone AS INT) = TRY_CAST(r.Zone AS INT)
   AND FLOOR(e.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
   AND e.[Charge Description] = r.ServiceTypeDescription
   AND e.[Container Type] = r.PackageCode
   AND e.[Billed Weight Unit of Measure] = r.WtUnit
   AND e.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
   AND (
        (r.Notes = 'Total' AND e.[Billed Weight] <= 150)
        OR
        (r.Notes = 'Per LB' AND e.[Billed Weight] > 150)
   )
   AND r.ChildID = 12661

        WHERE e.ControlNo = @ywControlno
    )

    -- ✅ 2. Insert matching rows into ups_base_rate_audit
    INSERT INTO dbo.ups_base_rate_audit (
        LeadShipmentNumber, ControlNo, ChildID, BillToAccountNo, InvoiceDt, BillOptionCode,
        ContainerType, TransactionDate, PackageQuantity, SenderCountry, ReceiverCountry,
        ChargeCategoryCode, ChargeClassificationCode, ChargeDescription,
        Zone, BilledWeight, BilledWeightUnitOfMeasure, NetAmount,
        ContractRate, PotentialError,
        SenderState, ReceiverState, InvoiceCurrencyCode
    )
    SELECT
        m.[Lead Shipment Number],
        m.ControlNo,
        m.ChildID,
        m.BillToAccountNo,
        m.InvoiceDt,
        m.[Bill Option Code],
        m.[Container Type],
        m.[Transaction Date],
        m.[Package Quantity],
        m.[Sender Country],
        m.[Receiver Country],
        m.[Charge Category Code],
        m.[Charge Classification Code],
        m.[Charge Description],
        m.Zone,
        m.[Billed Weight],
        m.[Billed Weight Unit of Measure],
        m.[Net Amount],
        CASE
            WHEN m.[Billed Weight] > 150 THEN m.Rate * m.[Billed Weight]
            WHEN m.MinRate IS NOT NULL AND m.Rate < m.MinRate THEN m.MinRate * m.[Package Quantity]
            ELSE m.Rate * m.[Package Quantity]
        END AS ContractRate,
        m.[Net Amount] - CASE
            WHEN m.[Billed Weight] > 150 THEN m.Rate * m.[Billed Weight]
            WHEN m.MinRate IS NOT NULL AND m.Rate < m.MinRate THEN m.MinRate * m.[Package Quantity]
            ELSE m.Rate * m.[Package Quantity]
        END AS PotentialError,
        m.[Sender State],
        m.[Receiver State],
        m.[Invoice Currency Code]
    FROM matched m
    WHERE rn = 1;

    -- ✅ 3. Insert unmatched shipments into ups_base_rate_audit_unmatched
    INSERT INTO dbo.ups_base_rate_audit_unmatched (
        LeadShipmentNumber, ControlNo, ChildID, BillToAccountNo, InvoiceDt, BillOptionCode,
        ContainerType, TransactionDate, PackageQuantity, SenderCountry, ReceiverCountry,
        ChargeCategoryCode, ChargeClassificationCode, ChargeDescription,
        Zone, BilledWeight, BilledWeightUnitOfMeasure, NetAmount,
        SenderState, ReceiverState, InvoiceCurrencyCode, ErrorReason
    )
    SELECT
        e.[Lead Shipment Number],
        e.ControlNo,
        e.ChildID,
        e.BillToAccountNo,
        e.InvoiceDt,
        e.[Bill Option Code],
        e.[Container Type],
        e.[Transaction Date],
        e.[Package Quantity],
        e.[Sender Country],
        e.[Receiver Country],
        e.[Charge Category Code],
        e.[Charge Classification Code],
        e.[Charge Description],
        e.Zone,
        e.[Billed Weight],
        e.[Billed Weight Unit of Measure],
        e.[Net Amount],
        e.[Sender State],
        e.[Receiver State],
        e.[Invoice Currency Code],
        'No matching rate found'
    FROM dbo.ups_ebill_prod e
    WHERE e.ControlNo = @ywControlno
    AND NOT EXISTS (
        SELECT 1
        FROM dbo.ups_rate_master r
        WHERE e.Zone = r.Zone
          AND FLOOR(e.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
          AND e.[Charge Description] = r.ServiceTypeDescription
          AND e.[Container Type] = r.PackageCode
          AND e.[Billed Weight Unit of Measure] = r.WtUnit
          AND e.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
          AND r.Notes = 'Total'
          AND r.ChildID = 12661
    );
END
