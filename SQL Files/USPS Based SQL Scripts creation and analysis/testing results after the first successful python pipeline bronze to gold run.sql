---- testing results after the first successful python pipeline bronze to gold run. 


select count(*)
from usps_ebill_prod

select *
from control_master




with cte as (
select p.ServiceLevel, p.BilledWeight_LB,p.[Zone],p.PackageCharge,r.Rate as [contract rate], (p.PackageCharge-r.Rate) as [potential error]
from TestDB.DBO.usps_ebill_prod as p 
left join TestDB.dbo.USPS_Rate_Master as r
on r.ServiceType=p.ServiceLevel
and CEILING(p.BilledWeight_LB)=r.Billed_Weight
and r.[Zone]=p.[Zone]

where CreatedDate >='2025-04-17 15:30:00.000')



select *
--select format(sum([potential error]),'c')
from cte

