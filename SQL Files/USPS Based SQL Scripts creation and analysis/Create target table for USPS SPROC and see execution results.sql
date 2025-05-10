
---------- Create USPS required tables, SPROC and Loop 3/24/2025. 


----- Step 1 : Create base table where the SPROC will send results to. 


----- Remove table from directory
--drop table TestDB.dbo.usps_base_rate_audit
---- Clear all records in table
--TRUNCATE TABLE TestDB.dbo.usps_base_rate_audit
select * from TestDB.dbo.usps_base_rate_audit


CREATE TABLE TestDB.dbo.usps_base_rate_audit (
    childid INT NOT NULL,
    [Tracking number] VARCHAR(50) NULL,
    controlno VARCHAR(50) NOT NULL,
    Shipdate DATE NULL,
	[Package Indicator] VARCHAR(150)  NULL, 
    [Service] VARCHAR(50) NULL,
    [BilledWeight_LB] FLOAT null,
    length FLOAT NULL,
    width FLOAT NULL,
    height FLOAT NULL,
    [Billed_Zone] VARCHAR(10) NULL,
    [cubic feet] FLOAT NULL,
    Tier VARCHAR(50) NULL,
    RN INT NULL,
    Billed_Amount FLOAT NULL,
    [Contract_Rate] FLOAT NULL,
    [PotentialError] FLOAT NULL,
    IsRated BIT NOT NULL DEFAULT 0
);



------------------------------ see results from stored procedure below. 
SELECT * FROM TestDB.dbo.control_master 


--- run all controlnos at once through the loop. 
exec [TestDB].[dbo].[base_rate_audit_loop_master]

--exec [TestDB].[dbo].[USPS_base_rate_audit_master] 800566


SELECT name
FROM sys.procedures
WHERE name LIKE '%loop%' AND name LIKE '%audit%';


 
SELECT controlno,childid,
FORMAT(SUM(CASE WHEN Contract_Rate IS NULL THEN 1 ELSE 0 END), 'N0') AS [Shipment Count NOT Rated],
FORMAT(SUM(CASE WHEN Contract_Rate IS NOT NULL THEN 1 ELSE 0 END), 'N0') AS [Shipment Count Rated],CASE 
WHEN SUM(CASE WHEN Contract_Rate IS NOT NULL THEN 1 ELSE 0 END) = 0 THEN NULL 
ELSE FORMAT(SUM(CASE WHEN Contract_Rate IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 'P2') END AS [Percent Rated],
FORMAT(SUM(CASE WHEN Contract_Rate IS NOT NULL THEN Billed_Amount ELSE 0 END), 'C') AS [Billed_Amount],
FORMAT(SUM(CASE WHEN Contract_Rate IS NOT NULL THEN Contract_Rate ELSE 0 END), 'C') AS [Contract_Rate],
FORMAT(SUM(CASE WHEN Contract_Rate IS NOT NULL THEN [PotentialError] ELSE 0 END), 'C') AS [PotentialError]
from TestDB.dbo.usps_base_rate_audit
--and shipdate>='2025-02-13'
group by controlno,childid
order by controlno,childid



---- grab all controlno's for sproc run. 
select distinct
'exec [TestDB].[dbo].[USPS_base_rate_audit_master]' as [Sproc header]
,controlno
from TestDB.dbo.usps_ebill_prod
where childid = 12659


exec [TestDB].[dbo].[USPS_base_rate_audit_master]	1004


delete from control_master
truncate table [TestDB].[dbo].[USPS_base_rate_audit]

TRUNCATE table [TestDB].[dbo].[usps_ebill_prod]


TRUNCATE table [TestDB].[dbo].[ups_ebill_prod]


SELECT controlno, count(*)
from TestDB.dbo.usps_base_rate_audit
where PotentialError is not null
group by controlno


select * from control_master 

delete from control_master where controlno = 1005

select * from usps_ebill_prod where controlno = 1007

select * from ups_ebill_prod 

select * from usps_base_rate_audit

select * from company_parent

select * from usps_base_Rate_audit


select controlno ,count(*)
from usps_ebill_prod
group by controlno
order by controlno asc


