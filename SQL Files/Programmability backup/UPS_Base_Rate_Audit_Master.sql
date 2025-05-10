
------- This code is taken from chatgpts memory used in condata's UPS stored procedures. 


USE [TNL_RATING]
GO
/****** Object:  StoredProcedure [dbo].[ups_base_rate_audit_master]    Script Date: 8/29/2024 12:46:51 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/***********************************************************************************************************

   Description:  ups_base_rate_audit_master

exec [tnl_rating].[dbo].[ups_base_rate_audit_master] 145189
--alter table tnl_rating.dbo.ups_base_rate_audit add [isHundredweight] int, [isNextDayEarly] int
***********************************************************************************************************/
ALTER PROCEDURE [dbo].[ups_base_rate_audit_master] @ywControlno AS INT
AS
SET NOCOUNT ON;

declare @ywchildid int
select @ywchildid = childid from tnl_reporting.dbo.control_master where ControlNo = @ywControlno


BEGIN

DROP TABLE IF EXISTS #ups_base_rate_audit_by_controlno
DROP TABLE IF EXISTS #ups_rate_master_by_childid

select top(1) * into #ups_base_rate_audit_by_controlno from tnl_rating.dbo.ups_base_rate_audit where controlno = @ywControlno
select * into #ups_rate_master_by_childid from tnl_rating.dbo.ups_rate_master where childid = @ywchildid
delete from #ups_base_rate_audit_by_controlno

-- Load the relevant columns from the UPS prod table into the temp table
    insert into #ups_base_rate_audit_by_controlno 
	select [Lead Shipment Number],[ControlNo],[ChildID],[BillToAccountNo],[InvoiceDt],
	[Bill Option Code],[Container Type],[Transaction Date],[Package Quantity],
	[Sender Country],[Receiver Country],[Charge Category Code],[Charge Classification Code],
	[Charge Description],[Zone],[Billed Weight],[Billed Weight Unit of Measure],
	[Net Amount],NULL,NULL,[Incentive Amount] + [Net Amount], [Sender State], [Receiver State], [Invoice Currency Code], 0, case when [Charge Description] like '%Early%' then 1 else 0 end, null
	from tnl_ups.dbo.ups_ebill_prod
	where controlno = @ywControlno
	AND [Charge Category Code] in ('SHP','RTN') and [Charge Category Detail Code] not in ('ASD') --don't include Air Shipping Document records
	AND [Charge Classification Code] in ('FRT')
	AND [Bill Option Code] not in ('DTP','DFC')
	and [Charge Description] not like '%Hundred%' --Take care of the Hundredweight shipments next
	and [Invoice Currency Code] != 'CAD' --Take care of Canadian UPS shipments later because they have per-piece minimums for multi-piece shipments

	insert into #ups_base_rate_audit_by_controlno
	select [Lead Shipment Number],max([ControlNo])as'ControlNo',max([ChildID])as'ChildID',max([BillToAccountNo])as'BillToAccountNo',max([InvoiceDt])as'InvoiceDt',
	max([Bill Option Code])as'Bill Option Code',max([Container Type])as'Container Type',max([Transaction Date])as'Transaction Date',sum([Package Quantity])as'Package Quantity',
	max([Sender Country])as'Sender Country',max([Receiver Country])as'Receiver Country',max([Charge Category Code])as'Charge Category Code',max([Charge Classification Code])as'Charge Classificatoin Code',
	max([Charge Description])as'Charge Description',max([Zone])as'Zone',sum([Billed Weight])as'Billed Weight',max([Billed Weight Unit of Measure])as'Billed Weight Unit of Measure',
	sum([Net Amount])as'Net Amount',NULL,NULL,sum([Incentive Amount]) + sum([Net Amount])as'Published Rate',max([Sender State])as'Sender State',max([Receiver State])as'Receiver State', max([Invoice Currency Code]) as 'Invoice Currency Code', 1,  0 , null
	from tnl_ups.dbo.ups_ebill_prod
	where controlno = @ywControlno
	AND [Charge Category Code] in ('SHP','RTN') and [Charge Category Detail Code] not in ('ASD') --don't include Air Shipping Document records
	AND [Charge Classification Code] in ('FRT')
	AND [Bill Option Code] not in ('DTP','DFC')
	and [Charge Description] like '%Hundred%'
	and [Invoice Currency Code] != 'CAD' --Take care of Canadian UPS shipments later because they have per-piece minimums for multi-piece shipments
	group by [Lead Shipment Number]

-- This select statement is grouped by Lead Shipment Number because sometimes there are multiple packages in a shipment, so you need to sum up the package quantity, weight, and net amount. HOWEVER, 
-- this was phased out by Jonathan Ong on 2/8/2023 due to the fact that multipiece shipments under the same Lead Shipment Number are still priced individually in the US. The Canadian UPS Shipments still
-- need to handle multi-piece shipments separately, so that was re-written below
/*	insert into tnl_rating.dbo.ups_base_rate_audit 
	select [Lead Shipment Number],max([ControlNo])as'ControlNo',max([ChildID])as'ChildID',max([BillToAccountNo])as'BillToAccountNo',max([InvoiceDt])as'InvoiceDt',
	max([Bill Option Code])as'Bill Option Code',max([Container Type])as'Container Type',max([Transaction Date])as'Transaction Date',sum([Package Quantity])as'Package Quantity',
	max([Sender Country])as'Sender Country',max([Receiver Country])as'Receiver Country',max([Charge Category Code])as'Charge Category Code',max([Charge Classification Code])as'Charge Classificatoin Code',
	max([Charge Description])as'Charge Description',max([Zone])as'Zone',sum([Billed Weight])as'Billed Weight',max([Billed Weight Unit of Measure])as'Billed Weight Unit of Measure',
	sum([Net Amount])as'Net Amount',NULL,NULL,sum([Incentive Amount]) + sum([Net Amount])as'Published Rate'
	from tnl_ups.dbo.ups_ebill_prod
	where controlno = @ywControlno
	AND [Charge Category Code] in ('SHP','RTN')
	AND [Charge Classification Code] in ('FRT')
	AND [Bill Option Code] not in ('DTP','DFC')
	group by [Lead Shipment Number] */

-- This next block takes care of Canadian UPS shipments. They need to be grouped by Lead Shipment Number because sometimes they will have per-piece minimum charges
	insert into #ups_base_rate_audit_by_controlno
	select [Lead Shipment Number],max([ControlNo])as'ControlNo',max([ChildID])as'ChildID',max([BillToAccountNo])as'BillToAccountNo',max([InvoiceDt])as'InvoiceDt',
	max([Bill Option Code])as'Bill Option Code',max(case when [Billed Weight Type] = '30' then 'PKG' else [Container Type] end)as'Container Type',max([Transaction Date])as'Transaction Date',sum([Package Quantity])as'Package Quantity',
	max([Sender Country])as'Sender Country',max([Receiver Country])as'Receiver Country',[Charge Category Code]as'Charge Category Code',max([Charge Classification Code])as'Charge Classificatoin Code',
	max([Charge Description])as'Charge Description',[Zone]as'Zone',sum([Billed Weight])as'Billed Weight',max([Billed Weight Unit of Measure])as'Billed Weight Unit of Measure',
	sum([Net Amount])as'Net Amount',NULL,NULL,sum([Incentive Amount]) + sum([Net Amount])as'Published Rate',max([Sender State])as'Sender State',max([Receiver State])as'Receiver State', max([Invoice Currency Code]) as 'Invoice Currency Code', 0,  0 , null
	from tnl_ups.dbo.ups_ebill_prod
	where controlno = @ywControlno
	AND [Charge Category Code] in ('SHP','RTN') and [Charge Category Detail Code] not in ('ASD') --don't include Air Shipping Document records
	AND [Charge Classification Code] in ('FRT')
	AND [Bill Option Code] not in ('DTP','DFC')
	and [Charge Description] not like '%Hundred%' --Take care of the Hundredweight shipments next
	and [Invoice Currency Code] = 'CAD' --this makes sure we're dealing with Canadian UPS shipments
	group by [Lead Shipment Number],[Charge Category Code],[Zone]
	
	update a set [Net Amount] = b.[Net Amount]
	from #ups_base_rate_audit_by_controlno a
	left join (select ControlNo,[Lead Shipment Number],[Tracking Number],[Net Amount] from tnl_ups.dbo.ups_ebill_prod where controlno = @ywControlno and [Charge Classification Code] = 'ACC' and [Charge Description Code] = 'FRT' and [Charge Description] = 'Freight') b
	  on a.ControlNo = b.ControlNo and a.[Lead Shipment Number] = b.[Lead Shipment Number] and b.[Net Amount] is not null and b.[Net Amount] > 0
	where a.childid = 12323  and b.[Net Amount] is not null--only Columbia Sportswear needs this query to update their Net Amounts for certain International Shipments

-- Find the contract rate by matching the shipment characteristics to the contract rate table: ups_rate_master
	UPDATE a -- this code block needs to ignore per-pound rates because those are handled next
	set ContractRate = round(b.[Rate],2)
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
	  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND (a.[Billed Weight Unit of Measure] = b.[WtUnit] or a.[Container Type] = 'LTR')
	  AND ( (ceiling(cast(a.[Billed Weight] as float)) > b.[MinWeight] AND ceiling(cast(a.[Billed Weight] as float)) <= b.[MaxWeight]) or (a.[Container Type] = 'LTR' and a.[Billed Weight] = 0 and b.MinWeight = 0))
	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Total' -- ignore per-pound rates and Discounts. 'Total' = the flat dollar amount that should be charged. 'Per Lb' = dollar amount per pound. 'Discount' = contract discount amount to be deducted from published rate
	  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
	  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'

			--THIS SUBSECTION HANDLES 'NEXT DAY AIR EARLY'
			UPDATE a -- this code block needs to ignore per-pound rates because those are handled next
			set ContractRate = round(b.[Rate],2)
			from #ups_base_rate_audit_by_controlno a
			left join #ups_rate_master_by_childid b on
				  a.[Transaction Date] >= b.EffectiveDate
			  AND a.[Transaction Date] <= b.ExpirationDate
			  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
			  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
			  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
			  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
			  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
			  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
			  AND (a.[Billed Weight Unit of Measure] = b.[WtUnit] or a.[Container Type] = 'LTR')
			  AND ( (ceiling(cast(a.[Billed Weight] as float)) > b.[MinWeight] AND ceiling(cast(a.[Billed Weight] as float)) <= b.[MaxWeight]) or (a.[Container Type] = 'LTR' and a.[Billed Weight] = 0 and b.MinWeight = 0))
			  and b.ServiceTypeDescription like '%Early%'
			  WHERE a.controlno = @ywControlno
			  and b.[Notes] = 'Total' -- ignore per-pound rates
			  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
			  and a.[isNextDayEarly] = 1 --and a.[Charge Description] like '%Next Day Air Early%'



	UPDATE a  -- this code block handles per-pound rates
	set ContractRate = round(b.[Rate]*ceiling(cast(a.[Billed Weight] as float)),2)
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
      AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND a.[Billed Weight Unit of Measure] = b.[WtUnit]
	  AND ceiling(cast(a.[Billed Weight] as float)) > b.[MinWeight]
	  AND ceiling(cast(a.[Billed Weight] as float)) <= b.[MaxWeight]
	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Per Lb'
	  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
	  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'

			--THIS SUBSECTION HANDLES 'NEXT DAY AIR EARLY'
			UPDATE a  -- this code block handles per-pound rates
			set ContractRate = round(b.[Rate]*ceiling(cast(a.[Billed Weight] as float)),2)
			from #ups_base_rate_audit_by_controlno a
			left join #ups_rate_master_by_childid b on
				  a.[Transaction Date] >= b.EffectiveDate
			  AND a.[Transaction Date] <= b.ExpirationDate
			  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
			  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
			  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
			  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
			  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
			  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
			  AND a.[Billed Weight Unit of Measure] = b.[WtUnit]
			  AND ceiling(cast(a.[Billed Weight] as float)) > b.[MinWeight]
			  AND ceiling(cast(a.[Billed Weight] as float)) <= b.[MaxWeight]
			  and b.ServiceTypeDescription like '%Early%'
			  WHERE a.controlno = @ywControlno
			  and b.[Notes] = 'Per Lb'
			  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
			  and a.[isNextDayEarly] = 1 --and a.[Charge Description] like '%Next Day Air Early%'


	UPDATE a  -- this code block handles UPS Hundredweight services. Harley (10377) has a 15lb per piece min for Ground. Libbey (10363) has a 25lb per piece min for Ground.
	set ContractRate = round( b.[Rate] * ceiling( case when case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] > cast(a.[Billed Weight] as float) then case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] else cast(a.[Billed Weight] as float) end ) ,2)
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
	  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND a.[Billed Weight Unit of Measure] = b.[WtUnit]
	  AND ceiling( case when case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] > cast(a.[Billed Weight] as float) then case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] else cast(a.[Billed Weight] as float) end ) >= b.[MinWeight] --Libbey, 10363, uses the published mins of 25/20 for grd/air per package weights
	  AND ceiling( case when case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] > cast(a.[Billed Weight] as float) then case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] else cast(a.[Billed Weight] as float) end ) <= b.[MaxWeight] --Libbey, 10363, uses the published mins of 25/20 for grd/air per package weights
	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Per Lb'
	  and a.[isHundredweight] = 1 --and a.[Charge Description] like '%Hundred%'
	  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'
	  and b.ServiceTypeDescription like '%Hundred%'

	UPDATE a  -- this code block is the second part of handling UPS Hundredweight services. It takes care of the minimum. Harley (10377) has a 15lb per piece min for Ground. Libbey (10363) has a 25lb per piece min for Ground.
	set ContractRate = case when b.MinRate > a.ContractRate then b.MinRate else a.ContractRate end
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
      AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND a.[Billed Weight Unit of Measure] = b.[WtUnit]
	  AND ceiling( case when case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] > cast(a.[Billed Weight] as float) then case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] else cast(a.[Billed Weight] as float) end ) >= b.[MinWeight] --Libbey, 10363, uses the published mins of 25/20 for grd/air per package weights
	  AND ceiling( case when case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] > cast(a.[Billed Weight] as float) then case when a.[Zone] in ('302','303','304','305','306','307','308','002','003','004','005','006','007','008','044','045','046') then (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 25 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 15 else 20 end) else (case when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10363)) then 20 when a.childid in (select childid from tnl_reporting.dbo.company_child where parentid in (10377)) then 18 else 18 end) end * a.[Package Quantity] else cast(a.[Billed Weight] as float) end ) <= b.[MaxWeight] --Libbey, 10363, uses the published mins of 25/20 for grd/air per package weights	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Per Lb'
	  and a.[isHundredweight] = 1 --and a.[Charge Description] like '%Hundred%'
	  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'
	  and b.ServiceTypeDescription like '%Hundred%'


	UPDATE a -- this code block handles multi-piece shipments with a per-piece minimum charge
	set ContractRate = case when ContractRate > round(b.[MinRate],2) * a.[Package Quantity] then ContractRate else round(b.[MinRate],2) * a.[Package Quantity] end
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  --AND a.[ChildID] = b.[ChildID] --this match is no longer needed because the temp tables isolate the data to a single childid
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  AND (REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard') LIKE b.ServiceTypeDescription + '%' OR b.BillingCountry = 'CA')	----- Added "returns" to account for rating shipments that are the same as dom. standard vs returns dom. standard RD 5/24/24.  
	  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode] -- for avery dennison, treat 1lb LTR's as PAK's. Also account for Letters that weigh one pound or more- treat them as packages, except royal bank, treat their 1 lb letters as letters
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND a.[Billed Weight Unit of Measure] = b.[WtUnit]
	  AND ( (ceiling(cast(a.[Billed Weight] as float)) > b.[MinWeight] AND ceiling(cast(a.[Billed Weight] as float)) <= b.[MaxWeight]) or (a.[Container Type] = 'LTR' and a.[Billed Weight] = 0 and b.MinWeight = 0))
	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Total'
	  and a.[Invoice Currency Code] = 'CAD' --Only do this for Canadian shipments, as they're the ones that may have minimum charges per piece in a multi-piece shipment
	  and a.[Package Quantity] > 1

	UPDATE #ups_base_rate_audit_by_controlno -- this code block handles multi-piece shipments with a per-piece minimum charge where we want to ignore them for certain clients
	set ContractRate = null
	  WHERE controlno = @ywControlno
	  and [childid] in (select childid from tnl_reporting.dbo.company_child where parentid in (10328,10304) and carrier = 'ups') --fiserv and american greetings rates have multi-piece packages rated at individual package level but our code sums them up at the shipment level which throws it off
	  and [Package Quantity] > 1
	  and [isHundredWeight] = 0 --and [Charge Description] not like '%Hundredweight%'


-- This code was originally added to handle Columbia Sportswear's France rates which came as discount amounts. Prior to that, we only loaded net rates for UPS. Now we want to be able to handle discount %'s.
	UPDATE a -- this code block needs to ignore per-pound rates because those are handled next
	set ContractRate = case when b.MinRate * a.[Package Quantity] > round((1-b.[Rate])*[Published Rate],2) and a.ChildID in (select childid from tnl_reporting.dbo.company_child where parentid = 10405 and CompanyChildCountry = 'fr') and a.[Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and a.[Package Quantity] > 1 then b.MinRate * a.[Package Quantity] else round((1-b.[Rate])*[Published Rate],2) end
	from #ups_base_rate_audit_by_controlno a
	left join #ups_rate_master_by_childid b on
	      a.[Transaction Date] >= b.EffectiveDate
	  AND a.[Transaction Date] <= b.ExpirationDate
	  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
	  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
	  --AND (replace(a.[Charge Description],'WW ','Worldwide ') like b.ServiceTypeDescription + '%' or b.BillingCountry = 'CA')
	  AND (concat(REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard'),case when a.ChildID in (select childid from tnl_reporting.dbo.company_child where parentid = 10405 and CompanyChildCountry = 'fr') and a.[Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and a.[Package Quantity] > 1 then ' Multi' else '' end) like b.ServiceTypeDescription + '%' or b.BillingCountry = 'CA')
	  AND case when [Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and [Package Quantity] > 1 then 'Multi' else '' end = case when b.ServiceTypeDescription like '%multi%' then 'Multi' else '' end
	  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode]
	  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
	  AND (a.[Billed Weight Unit of Measure] = b.[WtUnit] or a.[Container Type] = 'LTR')
	  AND ( (ceiling(cast(a.[Billed Weight] as float)*2)/2 > b.[MinWeight] AND ceiling(cast(a.[Billed Weight] as float)*2)/2 <= b.[MaxWeight]) or (a.[Container Type] = 'LTR' and a.[Billed Weight] = 0 and b.MinWeight = 0))
	  WHERE a.controlno = @ywControlno
	  and b.[Notes] = 'Discount' -- 'Total' = the flat dollar amount that should be charged. 'Per Lb' = dollar amount per pound. 'Discount' = contract discount amount to be deducted from published rate
	  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
	  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'
	  and b.RecipientCountry is null --This handles non-country-specific discounts

		-- Columbia Sportswear's UPS contract in France had country-specific discounts for Germany and Spain for Export Transborder. I couldn't figure out how to write a single statment to make the code match on those countries AND ALSO match the generic discount when it was a different country. So I added a second block of code to handle specific country discounts.
		UPDATE a -- this code block needs to ignore per-pound rates because those are handled next
		set ContractRate = case when b.MinRate * a.[Package Quantity] > round((1-b.[Rate])*[Published Rate],2) and a.ChildID in (select childid from tnl_reporting.dbo.company_child where parentid = 10405 and CompanyChildCountry = 'fr') and a.[Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and a.[Package Quantity] > 1 then b.MinRate * a.[Package Quantity] else round((1-b.[Rate])*[Published Rate],2) end
		from #ups_base_rate_audit_by_controlno a
		left join #ups_rate_master_by_childid b on
			  a.[Transaction Date] >= b.EffectiveDate
		  AND a.[Transaction Date] <= b.ExpirationDate
		  AND (a.[Sender Country] = b.[ShipperCountry] or a.[Sender Country] is null or b.[ShipperCountry] is null or b.[ShipperCountry] = 'ALL')
		  AND (a.[Receiver Country] = b.[RecipientCountry] or a.[Receiver Country] is null or b.[RecipientCountry] is null or b.[RecipientCountry] = 'ALL')
		  --AND (replace(a.[Charge Description],'WW ','Worldwide ') like b.ServiceTypeDescription + '%' or b.BillingCountry = 'CA')
		  AND (concat(REPLACE(REPLACE(a.[Charge Description], 'WW ', 'Worldwide '), 'Returns Dom. Standard', 'Dom. Standard'),case when a.ChildID in (select childid from tnl_reporting.dbo.company_child where parentid = 10405 and CompanyChildCountry = 'fr') and a.[Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and a.[Package Quantity] > 1 then ' Multi' else '' end) like b.ServiceTypeDescription + '%' or b.BillingCountry = 'CA')
		  AND case when [Charge Description] in ('Dom. Standard','Retours Dom. Standard','TB Standard','Retours TB Standard','TB Standard Undeliverable Return') and [Package Quantity] > 1 then 'Multi' else '' end = case when b.ServiceTypeDescription like '%multi%' then 'Multi' else '' end
		  AND case when a.[Container Type] = 'LTR' and [Billed Weight] between 1 and 2 and a.ChildID in (select ChildID from tnl_reporting.dbo.company_child where parentid = 10397 and Carrier = 'ups') and [Charge Description] like '%Worldwide%' then 'PAK' when a.[Container Type] = 'LTR' and [Billed Weight] >= case when a.childid = 11293 then 2 else 1 end and [Billed Weight Unit of Measure] = 'L' then 'PKG' else a.[Container Type] end = b.[PackageCode]
		  AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL')
		  AND (a.[Billed Weight Unit of Measure] = b.[WtUnit] or a.[Container Type] = 'LTR')
		  AND ( (ceiling(cast(a.[Billed Weight] as float)*2)/2 > b.[MinWeight] AND ceiling(cast(a.[Billed Weight] as float)*2)/2 <= b.[MaxWeight]) or (a.[Container Type] = 'LTR' and a.[Billed Weight] = 0 and b.MinWeight = 0))
		  WHERE a.controlno = @ywControlno
		  and b.[Notes] = 'Discount' -- 'Total' = the flat dollar amount that should be charged. 'Per Lb' = dollar amount per pound. 'Discount' = contract discount amount to be deducted from published rate
		  and a.[isHundredweight] = 0 --and a.[Charge Description] not like '%Hundred%'
		  and a.[isNextDayEarly] = 0 --and a.[Charge Description] not like '%Next Day Air Early%'
		  and b.RecipientCountry is not null --This handles country-specific discounts


-- Set the potential error amount to be the difference between the billed amount and the contract amount
	UPDATE #ups_base_rate_audit_by_controlno 
	set [PotentialError] = [Net Amount] - [ContractRate]
	where controlno = @ywControlno

-- Remove records where we couldn't pull in the actual charge
	delete from #ups_base_rate_audit_by_controlno 
	  where ControlNo = @ywControlno and [Net Amount] = 0

-- delete the old data from the ups base rate audit table
	delete from tnl_rating.dbo.ups_base_rate_audit where controlno = @ywControlno
-- insert the new data into the ups base rate audit table
    insert into tnl_rating.dbo.ups_base_rate_audit select * from #ups_base_rate_audit_by_controlno
	
DROP TABLE IF EXISTS #ups_base_rate_audit_by_controlno
DROP TABLE IF EXISTS #ups_rate_master_by_childid

END