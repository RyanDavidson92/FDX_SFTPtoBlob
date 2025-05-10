

----- Create control master table 
----- Used to track batch uploads and referential integrity


CREATE TABLE TestDB.DBO.control_master (
    ControlNo INT IDENTITY(800564, 1) PRIMARY KEY,  -- Starts at 800564
    ControlDate DATE,
    Carrier VARCHAR(50) DEFAULT 'USPS',
    SourceFile VARCHAR(100),
    CreatedBy VARCHAR(50),
    CreatedDate DATETIME DEFAULT GETDATE()
);

------ Set indentity insert to ON before adding controlno into controlmaster table. 
SET IDENTITY_INSERT TestDB.DBO.control_master ON;
-- [Insert block goes here]
SET IDENTITY_INSERT TestDB.DBO.control_master OFF;

-- Insert all ControlNos already used in the child table
INSERT INTO TestDB.DBO.control_master (ControlNo, ControlDate, SourceFile, CreatedBy)
SELECT DISTINCT ControlNo, GETDATE(), 'Backfill', 'System'
FROM usps_ebill_prod
WHERE ControlNo NOT IN (
    SELECT ControlNo FROM TestDB.DBO.control_master
);


------ This command adds the foreign key contstraint. 
ALTER TABLE usps_ebill_prod
ADD CONSTRAINT FK_usps_ebill_prod_ControlNo
    FOREIGN KEY (ControlNo)
    REFERENCES control_master(ControlNo)
    ON DELETE CASCADE;



-- Optional safety check --- check for every controlno (batch id) in the prod table. 
SELECT DISTINCT ControlNo
FROM usps_ebill_prod
WHERE ControlNo IS NOT NULL;




drop table control_master

select * from control_master














----- Because Controlno is a foreign key constraint, i cant insert records into usps_ebill_prod without first having a controlno in here first. 

IF NOT EXISTS (
    SELECT 1 FROM TestDB.DBO.control_master WHERE ControlNo = 800564
)
BEGIN
    INSERT INTO TestDB.DBO.control_master (
        ControlNo,
        ControlDate,
        Carrier,
        SourceFile,
        CreatedBy
    )
    VALUES (
        800564,
        GETDATE(),
        'USPS',
        'usps_batch_upload.csv',
        'test_user'
    );
END;



ALTER TABLE TestDB.DBO.control_master
ADD CONSTRAINT DF_control_master_carrier DEFAULT 'USPS' FOR Carrier;






CREATE TABLE TestDB.DBO.usps_ebill_prod (
    ID INT IDENTITY(1,1), --- used as a foreign key useful for tracking batch uploads. 
    ControlNo INT NOT NULL, ---- Use this as primary key 
    ChildID INT,
    TrackingNumber VARCHAR(50) NOT NULL, ---- Use this as primary key 
    InvoiceNumber VARCHAR(30),
    InvoiceDate DATE,
    ShipDate DATE,
    Length int NULL,
    Height int null, 
    Width int null, 
    DimUOM Varchar(50) null,
    ServiceLevel VARCHAR(50),
    ShipperNumber VARCHAR(50),
    OriginZip VARCHAR(10),
    DestinationZip VARCHAR(10),
    Zone INT,
    BilledWeight_LB DECIMAL(6,2),
    WeightUnit VARCHAR(5) DEFAULT 'LB',
    PackageCharge DECIMAL(10,2),
    FuelSurcharge DECIMAL(10,2),
    ResidentialSurcharge DECIMAL(10,2),
    DASCharge DECIMAL(10,2),
    TotalCharge DECIMAL(10,2),
    AccessorialCode VARCHAR(20),
    AccessorialDescription VARCHAR(100),
    PackageStatus VARCHAR(20),
    ReceiverName VARCHAR(100),
    ReceiverCity VARCHAR(50),
    ReceiverState VARCHAR(20),
    ReceiverCountry VARCHAR(50),
    CreatedDate DATETIME DEFAULT GETDATE(),

    -- Unique constraint on natural key
    CONSTRAINT UQ_Tracking_Control UNIQUE (TrackingNumber, ControlNo),

    -- Foreign key to control table
    CONSTRAINT FK_usps_ebill_prod_ControlNo FOREIGN KEY (ControlNo)
        REFERENCES TestDB.DBO.control_master(ControlNo)
        ON DELETE CASCADE  -- Optional: deletes child rows if parent is deleted
);




--- This table is populated and ready for auditing 
select * from usps_rate_master
select * from usps_ebill_prod


drop table usps_ebill_prod
delete from usps_ebill_prod




select * from usps_ebill_prod
where controlno = 800567





----- Use this to mirror production data packagecharges to the new rate sheet - having most packagecharges be correct simulates realism. 
UPDATE P
SET P.PackageCharge = R.Rate
FROM usps_ebill_prod P
JOIN usps_rate_master R
    ON P.ServiceLevel = R.ServiceType
   AND P.Zone = R.ZONE
and CEILING(P.BilledWeight_LB) = R.billed_weight



----- Run this for my independant control test. This purposely creates wrong rates for test purposes. 
UPDATE P
SET P.PackageCharge = ROUND(RAND(CHECKSUM(NEWID())) * 9 + 1, 2)
FROM (
    SELECT TOP 9 *
    FROM usps_ebill_prod
    ORDER BY NEWID()
) AS P;







------- Generate fake production data for production table.

WITH Numbers AS (
    SELECT TOP 500 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
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
    800564 AS ControlNo,
    12659 AS ChildID,
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
    (SELECT TOP 1 value FROM (VALUES 
        ('Signature Confirmation'), 
        ('Insurance'), 
        ('Return Receipt')) AS t(value) ORDER BY NEWID()),
    (SELECT TOP 1 value FROM (VALUES ('Delivered'), ('In Transit'), ('Return to Sender')) AS t(value) ORDER BY NEWID()),
    'Receiver ' + CAST(ABS(CHECKSUM(NEWID())) % 1000 AS VARCHAR),
    (SELECT TOP 1 value FROM (VALUES ('Miami'), ('Denver'), ('Seattle'), ('Boston'), ('Phoenix')) AS t(value) ORDER BY NEWID()),
    (SELECT TOP 1 value FROM (VALUES ('FL'), ('CO'), ('WA'), ('MA'), ('AZ')) AS t(value) ORDER BY NEWID()),
    'USA',
    ABS(CHECKSUM(NEWID())) % 20 + 1,  -- Length (1–20 inches)
    ABS(CHECKSUM(NEWID())) % 20 + 1,  -- Height (1–20 inches)
    ABS(CHECKSUM(NEWID())) % 20 + 1,  -- Width (1–20 inches)
    'IN'  -- DimUOM
FROM Numbers n
JOIN ServiceMap sm ON n.n = sm.n;
GO
