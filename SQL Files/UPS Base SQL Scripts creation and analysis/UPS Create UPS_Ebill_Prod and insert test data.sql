

----- Second step in creating UPS audit. This file will create the UPS ebill Prod table 



/*
CREATE TABLE TestDB.dbo.ups_ebill_prod (
    [Lead Shipment Number] VARCHAR(50),
    [ControlNo] INT NOT NULL,
    [ChildID] INT NOT NULL,
    [BillToAccountNo] VARCHAR(50),
    [InvoiceDt] DATE,
    [Bill Option Code] VARCHAR(10),
    [Container Type] VARCHAR(10),
    [Transaction Date] DATE,
    [Package Quantity] INT,
    [Sender Country] VARCHAR(10),
    [Receiver Country] VARCHAR(10),
    [Charge Category Code] VARCHAR(10),
    [Charge Classification Code] VARCHAR(10),
    [Charge Category Detail Code] VARCHAR(10),
    [Charge Description] VARCHAR(100),
    [Zone] VARCHAR(10),
    [Billed Weight] FLOAT,
    [Billed Weight Unit of Measure] VARCHAR(5),
    [Billed Weight Type] VARCHAR(10),
    [Net Amount] NUMERIC(10,2),
    [Incentive Amount] NUMERIC(10,2),
    [Tracking Number] VARCHAR(50),
    [Sender State] VARCHAR(10),
    [Receiver State] VARCHAR(10),
    [Invoice Currency Code] VARCHAR(10),
    CONSTRAINT FK_ups_ebill_prod_controlno FOREIGN KEY ([ControlNo])
        REFERENCES TestDB.dbo.control_master ([ControlNo])
);
*/





select * from TestDB.dbo.ups_ebill_prod where controlno = 1007

select * from control_master where ControlNo = 1007

TRUNCATE  table TestDB.dbo.ups_ebill_prod

select * from control_master where controlno = 1007

delete from ups_base_rate_audit where controlno = 1007
delete from ups_ebill_prod where controlno = 1007
delete from usps_base_rate_audit where controlno = 1006
delete from control_master where controlno = 1007

select * from ups_ebill_prod where ControlNo = 1006

select * from ups_rate_master


-- This will set the identity seed to 1005, so the next insert becomes 1006
DBCC CHECKIDENT ('TestDB.dbo.control_master', RESEED, 1006);


select max(controlno) from control_master




-- ✅ Step 1: Insert control_master record for UPS test batch
INSERT INTO control_master (
    ClientID,
    FileName,
    RecordCount,
    LoadTimestamp,
    SourceSystem,
    FileHash
)
VALUES (
    12661,
    'ups_batch_test_reset_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + '.csv',
    277,
    GETDATE(),
    'reset_test',
    NULL
);

-- ✅ Step 2: Capture new ControlNo
DECLARE @NewControlNo INT = SCOPE_IDENTITY();
SELECT @NewControlNo AS NewControlNo;

-- ✅ Step 3: Generate clean UPS records with correct service/zone/weight logic
WITH Numbers AS (
    SELECT TOP 277 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS rownum
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
ServiceMap AS (
    SELECT 
        rownum,
        CASE 
            WHEN rownum % 3 = 1 THEN '2nd Day Air'
            WHEN rownum % 3 = 2 THEN 'Next Day Air'
            ELSE 'Ground Commercial'
        END AS ServiceType,
        CASE 
            WHEN rownum % 3 = 1 THEN 'LTR'
            WHEN rownum % 3 = 2 THEN 'PKG'
            ELSE 'PKG'
        END AS ContainerType,
        CASE 
        WHEN rownum % 3 = 1 THEN 'O'  -- ✅ ounces for LTR
        ELSE 'L'
        END AS WtUnit,
        CASE 
            WHEN rownum % 3 = 1 THEN CAST(202 + ABS(CHECKSUM(NEWID())) % 6 AS VARCHAR)
            WHEN rownum % 3 = 2 THEN CAST(102 + ABS(CHECKSUM(NEWID())) % 6 AS VARCHAR)
            ELSE CAST(2 + ABS(CHECKSUM(NEWID())) % 7 AS VARCHAR)
        END AS Zone,
        CASE 
        WHEN rownum % 3 = 1 THEN 8  -- ✅ 8 ounces for LTR
        ELSE CAST(CEILING(RAND(CHECKSUM(NEWID())) * 249 + 1) AS FLOAT)
        END AS BilledWeight
    FROM Numbers
)

INSERT INTO TestDB.dbo.ups_ebill_prod (
    [Lead Shipment Number], ControlNo, ChildID, [BillToAccountNo], InvoiceDt, [Bill Option Code],
    [Container Type], [Transaction Date], [Package Quantity],
    [Sender Country], [Receiver Country], [Charge Category Code], [Charge Classification Code], [Charge Category Detail Code],
    [Charge Description], Zone, [Billed Weight], [Billed Weight Unit of Measure], [Billed Weight Type],
    [Net Amount], [Incentive Amount], [Tracking Number], [Sender State], [Receiver State], [Invoice Currency Code]
)
SELECT 
    '1Z' + RIGHT('000000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000 AS VARCHAR), 9),
    @NewControlNo,
    12661,
    'UPSACC' + CAST(((n.rownum - 1) % 4) + 1 AS VARCHAR),  -- UPSACC1 to UPSACC4 evenly distributed
    DATEADD(DAY, -n.rownum % 30, GETDATE()),
    'PRE',
    sm.ContainerType,
    DATEADD(DAY, -n.rownum % 35, GETDATE()),
    1,
    'US',
    'US',
    'SHP',
    'FRT',
    NULL,
    sm.ServiceType,
    sm.Zone,
    sm.BilledWeight,
    sm.WtUnit,
    '30',
    0.00,
    0.00,
    '1Z' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000 AS VARCHAR),
    'NY',
    'CA',
    'USD'
FROM Numbers n
JOIN ServiceMap sm ON n.rownum = sm.rownum;


-- Step 4A: Flat rate for Ground Commercial (Notes = 'Total')
UPDATE p
SET p.[Net Amount] = r.Rate
FROM TestDB.dbo.ups_ebill_prod p
JOIN TestDB.dbo.ups_rate_master r
    ON p.ControlNo = @NewControlNo
    AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
    AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
    AND p.[Charge Description] = r.ServiceTypeDescription
    AND p.[Container Type] = r.PackageCode
    AND p.[Billed Weight Unit of Measure] = r.WtUnit
    AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
    AND r.Notes = 'Total'
    AND r.ChildID = 12661
WHERE p.[Charge Description] = 'Ground Commercial'
  AND p.[Net Amount] = 0.00;


-- Step 4B: Apply rate * weight for heavyweights (>150 lbs)
UPDATE p
SET p.[Net Amount] = p.[Billed Weight] * r.Rate
FROM TestDB.dbo.ups_ebill_prod p
JOIN TestDB.dbo.ups_rate_master r
    ON p.ControlNo = @NewControlNo
    AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
    AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
    AND p.[Charge Description] = r.ServiceTypeDescription
    AND p.[Container Type] = r.PackageCode
    AND p.[Billed Weight Unit of Measure] = r.WtUnit
    AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
    AND r.Notes = 'Per LB'
    AND r.ChildID = 12661
WHERE p.[Billed Weight] > 150;


-- Step 4C: Flat rate for Air (Notes = 'Total')
UPDATE p
SET p.[Net Amount] = r.Rate
FROM TestDB.dbo.ups_ebill_prod p
JOIN TestDB.dbo.ups_rate_master r
    ON p.ControlNo = @NewControlNo
    AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
    AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
    AND p.[Charge Description] = r.ServiceTypeDescription
    AND p.[Container Type] = r.PackageCode
    AND p.[Billed Weight Unit of Measure] = r.WtUnit
    AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
    AND r.Notes = 'Total'
    AND r.ChildID = 12661
WHERE p.[Charge Description] IN ('Next Day Air', '2nd Day Air')
  AND p.[Billed Weight] <= 150
  AND p.[Net Amount] = 0.00;


-- Step 4D: Per-pound rate for Air heavyweight (Notes = 'Per LB')
UPDATE p
SET p.[Net Amount] = p.[Billed Weight] * r.Rate
FROM TestDB.dbo.ups_ebill_prod p
JOIN TestDB.dbo.ups_rate_master r
    ON p.ControlNo = @NewControlNo
    AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
    AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
    AND p.[Charge Description] = r.ServiceTypeDescription
    AND p.[Container Type] = r.PackageCode
    AND p.[Billed Weight Unit of Measure] = r.WtUnit
    AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
    AND r.Notes = 'Per LB'
    AND r.ChildID = 12661
WHERE p.[Charge Description] IN ('Next Day Air', '2nd Day Air')
  AND p.[Billed Weight] > 150
  AND p.[Net Amount] = 0.00;




UPDATE p
SET p.[Net Amount] = r.Rate
FROM TestDB.dbo.ups_ebill_prod p
JOIN TestDB.dbo.ups_rate_master r
    ON p.ControlNo = 1006
    AND TRY_CAST(p.Zone AS INT) = TRY_CAST(r.Zone AS INT)
    AND p.[Charge Description] = r.ServiceTypeDescription
    AND p.[Container Type] = r.PackageCode
    AND p.[Billed Weight Unit of Measure] = r.WtUnit
    AND FLOOR(p.[Billed Weight]) BETWEEN r.MinWeight AND r.MaxWeight
    AND p.[Transaction Date] BETWEEN r.EffectiveDate AND r.ExpirationDate
    AND r.Notes = 'Total'
    AND r.ChildID = 12661
WHERE p.[Charge Description] = '2nd Day Air'
  AND p.[Container Type] = 'LTR'
  AND p.[Net Amount] = 0.00;





-- Step 5: Update 30 random Ground Commercial Zone 4 shipments with incorrect Net Amounts, isolated to only ground commercial zone 4 to test api llm accuracy when applied. 
WITH RandomRows AS (
    SELECT TOP 30 p.[Lead Shipment Number]
    FROM TestDB.dbo.ups_ebill_prod p
    WHERE p.ControlNo = @NewControlNo
      AND p.[Charge Description] = 'Ground Commercial'
      and p.BillToAccountNo = 'UPSACC3'
      --AND TRY_CAST(p.[Zone] AS INT) = 4
    ORDER BY NEWID()
)
UPDATE p
SET p.[Net Amount] = CAST(ROUND(RAND(CHECKSUM(NEWID())) * (200.00 - 10.00) + 10.00, 2) AS DECIMAL(10,2))
FROM TestDB.dbo.ups_ebill_prod p
JOIN RandomRows r ON p.[Lead Shipment Number] = r.[Lead Shipment Number];

