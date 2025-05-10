




----- Use this to apply new auto - incremental controlnos into the controlmaster for the usps stored procedure to work. 
select * from control_master

select * FROM usps_ebill_prod

---- use this to re-seed the prod table for testing purposes. 
DELETE FROM usps_ebill_prod
WHERE ControlNo >= 800565;
---- remove old controlnos 
DELETE FROM control_master
WHERE ControlNo >= 1000;

----- Reseed identity back to 1000
DBCC CHECKIDENT ('control_master', RESEED, 1000);





-- ✅ Insert a test row to confirm reseed worked
INSERT INTO control_master (
    ClientID,
    FileName,
    RecordCount,
    LoadTimestamp,
    SourceSystem,
    FileHash
)
VALUES (
    12659,                                 -- 👈 INT, not string
    'usps_batch_test_reset.csv',
    2000,
    GETDATE(),
    'reset_test',
    NULL
);

-- ✅ Return the new ControlNo
SELECT SCOPE_IDENTITY() AS NewControlNo;



-- 🔁 Step 1: Delete old test records
DELETE FROM usps_ebill_prod
WHERE ControlNo >= 1000;

-- 🔁 Step 2: Delete old test records
DELETE FROM usps_base_rate_audit
WHERE ControlNo >= 1000;

DELETE FROM control_master
WHERE ControlNo >= 1000;




DELETE FROM ups_base_rate_audit
DELETE FROM dbo.ups_ebill_prod;
DELETE FROM dbo.control_master;
DELETE FROM dbo.usps_ebill_prod;
DELETE FROM dbo.control_master;




-- 🔄 Step 2: Reseed ControlNo identity column
DBCC CHECKIDENT ('control_master', RESEED, 999);


select * from control_master

DELETE FROM control_master
WHERE ControlNo >= 1000;


select * from usps_ebill_prod
where controlno = 1002


------------ RUN THIS BELOW IN ONE SINGLE STEP -----------



-- ✅ Step 3: Insert a new test control record (uses new table structure)
INSERT INTO control_master (
    ClientID,
    FileName,
    RecordCount,
    LoadTimestamp,
    SourceSystem,
    FileHash
)
VALUES (
    12660,
    'usps_batch_test_reset_' + FORMAT(GETDATE(), 'yyyyMMdd_HHmmss') + '.csv',
    777,
    GETDATE(),
    'reset_test',
    NULL
);

-- ✅ Step 3.5: Capture the auto-generated ControlNo
DECLARE @NewControlNo INT = SCOPE_IDENTITY();

-- 📥 Step 4: Capture new ControlNo value
SELECT SCOPE_IDENTITY() AS NewControlNo;


-- Step 3: Generate 500 fake USPS eBill records tied to that ControlNo
WITH Numbers AS (
    SELECT TOP 777 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects a CROSS JOIN sys.all_objects b
),
ServiceMap AS (
    SELECT 
        n,
        CASE 
            WHEN n % 3 = 1 THEN 'Priority Mail'
            WHEN n % 3 = 2 THEN 'Priority Mail Express'
            ELSE 'USPS Ground Advantage'
        END AS ServiceLevel
    FROM Numbers
)
INSERT INTO TestDB.DBO.usps_ebill_prod (
    ControlNo, ChildID, TrackingNumber, InvoiceNumber, InvoiceDate, ShipDate,
    ServiceLevel, ShipperNumber, OriginZip, DestinationZip, Zone, BilledWeight_LB,
    WeightUnit, PackageCharge, FuelSurcharge, ResidentialSurcharge, DASCharge,
    TotalCharge, AccessorialCode, AccessorialDescription, PackageStatus,
    ReceiverName, ReceiverCity, ReceiverState, ReceiverCountry,
    Length, Height, Width, DimUOM
)
SELECT 
    @NewControlNo,
    12660,
    '9400' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000000000 AS VARCHAR),
    'USPSINV' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR),
    DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 60, GETDATE()),
    DATEADD(DAY, -ABS(CHECKSUM(NEWID())) % 65, GETDATE()),
    sm.ServiceLevel,
    '9400' + CAST(ABS(CHECKSUM(NEWID())) % 1000000000 AS VARCHAR),
    RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 99999 AS VARCHAR), 5),
    RIGHT('00000' + CAST(ABS(CHECKSUM(NEWID())) % 99999 AS VARCHAR), 5),
    ABS(CHECKSUM(NEWID())) % 8 + 1,
    CAST(ROUND(RAND(CHECKSUM(NEWID())) * 20 + 0.1, 2) AS DECIMAL(6,2)),
    'LB',
    CAST(ROUND(RAND(CHECKSUM(NEWID())) * 25 + 2, 2) AS DECIMAL(10,2)),
    0.0,
    0.0,
    0.0,
    0.0,
    'AC' + CAST(ABS(CHECKSUM(NEWID())) % 10 AS VARCHAR),
    desc_tbl.AccessorialDescription,
    status_tbl.PackageStatus,
    'Receiver ' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR),
    city_tbl.ReceiverCity,
    state_tbl.ReceiverState,
    'USA',
    ABS(CHECKSUM(NEWID())) % 20 + 1,
    ABS(CHECKSUM(NEWID())) % 20 + 1,
    ABS(CHECKSUM(NEWID())) % 20 + 1,
    'IN'
FROM Numbers n
JOIN ServiceMap sm ON n.n = sm.n
CROSS JOIN (
    SELECT TOP 1 value AS AccessorialDescription
    FROM (VALUES ('Signature Confirmation'), ('Insurance'), ('Return Receipt')) AS t(value)
    ORDER BY NEWID()
) desc_tbl
CROSS JOIN (
    SELECT TOP 1 value AS PackageStatus
    FROM (VALUES ('Delivered'), ('In Transit'), ('Return to Sender')) AS t(value)
    ORDER BY NEWID()
) status_tbl
CROSS JOIN (
    SELECT TOP 1 value AS ReceiverCity
    FROM (VALUES ('Miami'), ('Denver'), ('Seattle'), ('Boston'), ('Phoenix')) AS t(value)
    ORDER BY NEWID()
) city_tbl
CROSS JOIN (
    SELECT TOP 1 value AS ReceiverState
    FROM (VALUES ('FL'), ('CO'), ('WA'), ('MA'), ('AZ')) AS t(value)
    ORDER BY NEWID()
) state_tbl;


-- Step 4: Mirror rate sheet to simulate real billing accuracy
UPDATE P
SET P.PackageCharge = R.Rate
FROM usps_ebill_prod P
JOIN usps_rate_master R
    ON P.ServiceLevel = R.ServiceType
   AND P.Zone = R.ZONE
   AND CEILING(P.BilledWeight_LB) = R.billed_weight
WHERE P.ControlNo = @NewControlNo;


-- Step 5: Randomly override rows to simulate bad audit cases
UPDATE p
SET p.PackageCharge = ROUND(RAND(CHECKSUM(NEWID())) * 14 + 1, 2)
FROM (
    SELECT TOP 99 *
    FROM usps_ebill_prod
    WHERE ControlNo = @NewControlNo
    ORDER BY NEWID()
) AS p;
