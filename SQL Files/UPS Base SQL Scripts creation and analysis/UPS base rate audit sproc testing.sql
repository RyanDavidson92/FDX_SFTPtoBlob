
----- UPS base rate audit sproc testing


ALTER TABLE TestDB.dbo.ups_ebill_prod
ADD CONSTRAINT UQ_Tracking_Control_UPS UNIQUE ([Tracking Number], ControlNo);




select max(controlno) from control_master




select controlno, count(*)
from ups_ebill_prod
group by controlno 
order by controlno asc 




select * from control_master where ControlNo in ('1006', '1007')

delete from control_master where ControlNo in ('1006', '1007')


delete from ups_ebill_prod  where [ControlNo] = 1007

DELETE FROM dbo.ups_base_rate_audit
WHERE ControlNo IN (1006, 1007);



DELETE FROM dbo.ups_base_rate_audit_sanitized
WHERE ControlNo IN (1006, 1007);



DELETE FROM dbo.control_master
WHERE ControlNo IN (1006, 1007);

select * from control_master



select * from ups_ebill_prod where [ControlNo] = 1007


select controlno, count(*) 
from usps_ebill_prod 
group by ControlNo
order by controlno asc

select controlno, count(*) 
from ups_ebill_prod 
group by ControlNo
order by controlno asc



---- Wipe everything to start test over again. 
delete from dbo.usps_ebill_prod
delete from dbo.ups_ebill_prod
delete from dbo.ups_base_rate_audit
delete from dbo.usps_base_rate_audit
delete from dbo.control_master
delete from dbo.ups_base_rate_audit_sanitized



-- This will set the identity seed to 1005, so the next insert becomes 1006
DBCC CHECKIDENT ('TestDB.dbo.control_master', RESEED, 1005);




select * from ups_rate_master where childid = 12661 



select * from ups_base_rate_audit where controlno = 1007


select format(sum(potentialerror),'c') as [potentialerror]
from ups_base_rate_audit
where controlno = 1007


select distinct
'exec [TestDB].[DBO].[ups_base_rate_audit_master]', controlno 
from ups_ebill_prod



exec [TestDB].[DBO].[ups_base_rate_audit_master]	1006
exec [TestDB].[DBO].[ups_base_rate_audit_master]	1007



DELETE FROM dbo.ups_base_rate_audit_sanitized;
DELETE FROM dbo.ups_base_rate_audit;
delete from gpt_ups_summary_analysis;



select * from ups_ebill_prod where [Charge Description] = 'ground commercial' and zone = 4 and [Billed Weight]='31'
select * from ups_rate_master where [ServiceTypeDescription] = 'ground commercial' and zone = 4 and MaxWeight='31'


select * from dbo.ups_base_rate_audit_sanitized 

delete from dbo.ups_base_rate_audit



SELECT controlno,childid,
FORMAT(SUM(CASE WHEN ContractRate IS NULL THEN 1 ELSE 0 END), 'N0') AS [Shipment Count NOT Rated],
FORMAT(SUM(CASE WHEN ContractRate IS NOT NULL THEN 1 ELSE 0 END), 'N0') AS [Shipment Count Rated],CASE 
WHEN SUM(CASE WHEN ContractRate IS NOT NULL THEN 1 ELSE 0 END) = 0 THEN NULL 
ELSE FORMAT(SUM(CASE WHEN ContractRate IS NOT NULL THEN 1 ELSE 0 END) * 1.0 / COUNT(*), 'P2') END AS [Percent Rated],
FORMAT(SUM(CASE WHEN ContractRate IS NOT NULL THEN NetAmount ELSE 0 END), 'C') AS [Billed_Amount],
FORMAT(SUM(CASE WHEN ContractRate IS NOT NULL THEN ContractRate ELSE 0 END), 'C') AS [Contract_Rate],
FORMAT(SUM(CASE WHEN ContractRate IS NOT NULL THEN [PotentialError] ELSE 0 END), 'C') AS [PotentialError]
from TestDB.dbo.ups_base_rate_audit
--and shipdate>='2025-02-13'
group by controlno,childid
order by controlno,childid


select * from gpt_ups_summary_analysis



select * from ups_base_rate_audit as a left join ups_base_rate_audit_sanitized as s on a.hashkey=s.hashkey
where LeadShipmentNumber='1Z456503179'


--The Net Amount matches the rate for Zone 002, 6-7 lbs, indicating a potential mis-zoning or mis-weighing of the package.


select * from ups_rate_master where [Zone] = 2 and MaxWeight between 5 and 7 and ServiceTypeDescription = 'ground commercial'
select * from ups_rate_master where [Zone] = 3 and MaxWeight between 6 and 7 and ServiceTypeDescription = 'ground commercial'




select * from ups_base_rate_audit_sanitized 




CREATE TABLE dbo.gpt_ups_summary_analysis (
    ControlNo INT,
    AnalysisText NVARCHAR(MAX),
    Timestamp DATETIME DEFAULT GETDATE()
);

select * from gpt_ups_summary_analysis

