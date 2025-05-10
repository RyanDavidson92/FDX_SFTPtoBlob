
------- This FDX procedure is directly from chatgpt.

CREATE PROCEDURE [dbo].[fdx_base_rate_audit_master] @ywControlno AS INT
	,@ywShowResults AS INT = 0
AS
SET NOCOUNT ON;

BEGIN

	/* take all the records with a BundleNo present, and sum up the Weights and Charges for each Bundle */
	DROP TABLE IF EXISTS #fdx_base_rate_audit_bundles
	select min([Fkey]) as 'Fkey',min([ControlNo]) as 'ControlNo',min([ChildID]) as 'ChildID',min([AccountNo]) as 'AccountNo',min([InvoiceNo]) as 'InvoiceNo',min([InvoiceDT]) as 'InvoiceDT',min([TrackingNo]) as 'TrackingNo',min([GroundTrackingNo]) as 'GroundTrackingNo',min([PickupDT]) as 'PickupDT',min([ServiceTypeCode]) as 'ServiceTypeCode',min([Currency]) as 'Currency',min([Zone]) as 'Zone',sum(convert(float,[Pcs])) as 'Pcs',sum(convert(float,[BillWt])) as 'BillWt',min([WtUnit]) as 'WtUnit',min([ShipperState]) as 'ShipperState',min([ShipperCountry]) as 'ShipperCountry',min([RecipientState]) as 'RecipientState',min([RecipientCountry]) as 'RecipientCountry',min([Pkg]) as 'Pkg',min([GrdSvc]) as 'GrdSvc',min([Payor]) as 'Payor',[BundleNo],min([GrdMisc1]) as 'GrdMisc1',min([GrdMisc2]) as 'GrdMisc2',min([GrdMisc3]) as 'GrdMisc3',min([RevThresholdAmt]) as 'RevThresholdAmt',min([ZoneJump]) as 'ZoneJump',sum([FreightAmt]) as 'FreightAmt',sum([VolDiscAmt]) as 'VolDiscAmt',sum([EarnedDiscAmt]) as 'EarnedDiscAmt',sum([AutoDiscAmt]) as 'AutoDiscAmt',sum([PerfPriceAmt]) as 'PerfPriceAmt',sum([BilledDiscountPct]) as 'BilledDiscountPct',sum([BilledDiscountAmt]) as 'BilledDiscountAmt',sum([BilledNetFreightCharge]) as 'BilledNetFreightCharge',min([PublishedRate]) as 'PublishedRate',min([ContractDiscountPct]) as 'ContractDiscountPct',min([ContractDiscountAmt]) as 'ContractDiscountAmt',min([ContractMinNetCharge]) as 'ContractMinNetCharge',min([ContractNetFreightCharge]) as 'ContractNetFreightCharge',min([PotentialError]) as 'PotentialError',0 as 'isRated',min([AccountCategory]) as 'AccountCategory',min([LastYearsRate]) as 'LastYearsRate'
	into #fdx_base_rate_audit_bundles from tnl_rating.dbo.fdx_base_rate_audit where controlno = @ywControlno and bundleno > '' group by BundleNo
	delete from tnl_rating.dbo.fdx_base_rate_audit where controlno = @ywControlno and bundleno > ''
	insert into tnl_rating.dbo.fdx_base_rate_audit select * from #fdx_base_rate_audit_bundles
	DROP TABLE IF EXISTS #fdx_base_rate_audit_bundles

	/* update AccountCategory in the base_rate_audit_table to compare against the fdx_rate_master table */
	update shps set AccountCategory = case when cats.Category is null then '1' else cats.Category end --set default category = 1. If there are more categories, make sure to add them in the fdx_rate_master table
	from tnl_rating.dbo.fdx_base_rate_audit shps
	  left join tnl_rating.dbo.fdx_base_rate_audit_account_category cats 
	  on shps.AccountNo = cats.AccountNo
	  and shps.ServiceTypeCode = cats.ServiceTypeCode
	where controlno = @ywControlNo 

	/* calculate the discount amount and net freight-only charges from the client's invoice */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [BilledDiscountAmt] = [VolDiscAmt] + [EarnedDiscAmt] + [AutoDiscAmt] + [PerfPriceAmt]
		,[BilledDiscountPct] = round(CASE 
				WHEN [FreightAmt] = 0
					THEN NULL
				ELSE ([VolDiscAmt] + [EarnedDiscAmt] + [AutoDiscAmt] + [PerfPriceAmt]) / [FreightAmt] * - 1
				END, 4)
		,[BilledNetFreightCharge] = [FreightAmt] + [VolDiscAmt] + [EarnedDiscAmt] + [AutoDiscAmt] + [PerfPriceAmt]
	WHERE controlno = @ywControlNo  --001

	/* set the published rates */ 
	UPDATE tnl_rating.dbo.fdx_base_rate_audit -- First look for rates that are not per lb multipliers, search [Note] field to make sure it's not Per Lb
	SET PublishedRate = FreightAmt WHERE controlno = @ywControlno  /*b.Rate --Commenting this whole section out because FedEx invoices provide the published rate in the FreightAmt column
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON 
	        cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (a.[Pkg] = b.[ServicePackageCode] or b.[ServicePackageCode] = 'ALL' or b.[ServicePackageCode] is null)
		AND a.[ServiceTypeCode] = b.[ServiceTypeCode]
		AND a.[Zone] = b.[Zone]
		AND (a.[GrdSvc] = b.[GrdSvc] or b.[GrdSvc] = 'ALL' or b.[GrdSvc] is null)
		AND ceiling(cast([BillWt] AS FLOAT)) >= b.MinWeight
		AND ceiling(cast([BillWt] AS FLOAT)) <= b.MaxWeight
		AND (a.[ShipperCountry] = b.[ShipperCountry] or b.[ShipperCountry] is null)
		AND (a.[RecipientCountry] = b.[RecipientCountry] or b.[RecipientCountry] is null)
		AND b.[BillingCountry] = case when a.[Currency] = 'CAD' then 'CA' else 'US' end
	WHERE controlno = @ywControlNo
		AND b.ChildId = 1 --these are published rates
		AND (b.[Notes] != 'Per Lb' or b.[Notes] is null) -- First look for rates that are not per lb multipliers
		AND (a.[BundleNo] = '' or a.[BundleNo] is null) --bundled shipments will have rates that appear off because they are split among several packages in a shipments
		
	UPDATE tnl_rating.dbo.fdx_base_rate_audit -- Second look for rates that ARE per lb multipliers, search [Note] field to find Per Lb
	SET PublishedRate = b.Rate * ceiling(a.[BillWt])
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON 
	        cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (a.[Pkg] = b.[ServicePackageCode] or b.[ServicePackageCode] = 'ALL' or b.[ServicePackageCode] is null)
		AND a.[ServiceTypeCode] = b.[ServiceTypeCode]
		AND a.[Zone] = b.[Zone]
		AND (a.[GrdSvc] = b.[GrdSvc] or b.[GrdSvc] = 'ALL' or b.[GrdSvc] is null)
		AND ceiling(cast([BillWt] AS FLOAT)) >= b.MinWeight
		AND ceiling(cast([BillWt] AS FLOAT)) <= b.MaxWeight
		AND (a.[ShipperCountry] = b.[ShipperCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[ShipperCountry] is null))
		AND (a.[RecipientCountry] = b.[RecipientCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[RecipientCountry] is null))
		AND b.[BillingCountry] = case when a.[Currency] = 'CAD' then 'CA' else 'US' end
	WHERE controlno = @ywControlNo
		AND b.ChildId = 1 --these are published rates
		AND b.[Notes] = 'Per Lb' -- Second, look for rates that are per lb multipliers
		AND (a.[BundleNo] = '' or a.[BundleNo] is null) --bundled shipments will have rates that appear off because they are split among several packages in a shipments
		*/
	/* set the contract discount amounts */

	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractDiscountPct] = 0
	WHERE controlno = @ywControlNo 

	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractDiscountPct] = [ContractDiscountPct] + b.Discount
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON a.ChildID = b.ChildID
		AND cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (case when a.[Pkg] in ('03','04','13','23','33','43') then '01' when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = b.[ServicePackageCode] or case when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = concat('0',b.[ServicePackageCode]) )
		AND (case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = b.[ServiceTypeCode] or case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = concat('0',b.[ServiceTypeCode]) )--service matches
		AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL' or a.[Zone] = concat('0',b.[Zone]) or b.[Zone] = concat('0',a.[Zone])) -- zone matches or zone is null in the rate table which means it applies to all zones
		    AND ((NOT case when a.ShipperState is null then 'null' else a.Shipperstate end = 'PR' and isnull(b.ShipperState,'null') != 'PR') or a.ShipperState = b.ShipperState)
			AND ((NOT case when a.RecipientState is null then 'null' else a.RecipientState end = 'PR' and isnull(b.RecipientState,'null') != 'PR') or a.RecipientState = b.RecipientState)
		AND ((ceiling(cast([BillWt] AS FLOAT)) >= b.MinWeight AND ceiling(cast([BillWt] AS FLOAT)) <= b.MaxWeight) or (b.MinWeight is null and b.MaxWeight is null)) --weight matches or both weights are null
		--Ground service uses these main service codes: 019 (OB), 417 (3P), 422 (RB), 137 (RM), 021 (IB), 142 (Call Tag), 018 (PRP), 804 (OB), 850 (3P) so these are the only ones that need to be built in the rate template
		AND (b.[GrdSvc] = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
		    or concat('0',b.[GrdSvc]) = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
			or b.[GrdSvc] is null 
			or b.[GrdSvc] = 'ALL') --ground service matches or ground service is null
		--AND a.AccountCategory = b.AccountCategory --Original
		AND case when b.AccountCategory = 'ALL' then 9999 else b.AccountCategory end = case when b.AccountCategory = 'ALL' then 9999 else a.AccountCategory end		
		AND CASE 
			WHEN a.[ZoneJump] > ''
				THEN 1
			ELSE 0
			END = b.[ZJ] --zone jump matches. when the zone jump field in the prod table is non-blank, then it's a zone jump shipment
		AND (a.[ShipperCountry] = b.[ShipperCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[ShipperCountry] is null))
		AND (a.[RecipientCountry] = b.[RecipientCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[RecipientCountry] is null))
	WHERE controlno = @ywControlNo 
		AND b.ChildId = a.ChildID
		AND b.[Discount] is not null
		AND b.[Rate] is null
		AND b.[MinSpend] is null --handle revenue discount in the next code block

	UPDATE tnl_rating.dbo.fdx_base_rate_audit set revthresholdamt = case when revthresholdamt is null then (select top(1) revthresholdamt from tnl_rating.dbo.fdx_base_rate_audit where controlno = @ywControlNo and FreightAmt > '' and RevThresholdAmt > '' group by RevThresholdAmt order by count(RevThresholdAmt) desc) when revthresholdamt = 0 then (select top(1) revthresholdamt from tnl_rating.dbo.fdx_base_rate_audit where controlno = @ywControlNo and FreightAmt > '' and RevThresholdAmt > '' group by RevThresholdAmt order by count(RevThresholdAmt) desc) when RevThresholdAmt = '' then (select top(1) revthresholdamt from tnl_rating.dbo.fdx_base_rate_audit where controlno = @ywControlNo and FreightAmt > '' and RevThresholdAmt > '' group by RevThresholdAmt order by count(RevThresholdAmt) desc) else RevThresholdAmt end
	where controlno = @ywControlNo

	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractDiscountPct] = [ContractDiscountPct] + b.Discount
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON a.ChildID = b.ChildID
		AND cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (case when a.[Pkg] in ('03','04','13','23','33','43') then '01' when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = b.[ServicePackageCode] or case when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = concat('0',b.[ServicePackageCode]) )
		AND (case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = b.[ServiceTypeCode] or case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = concat('0',b.[ServiceTypeCode]) )--service matches
		AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL' or a.[Zone] = concat('0',b.[Zone]) or b.[Zone] = concat('0',a.[Zone])) -- zone matches or zone is null in the rate table which means it applies to all zones
		    AND ((NOT case when a.ShipperState is null then 'null' else a.Shipperstate end = 'PR' and isnull(b.ShipperState,'null') != 'PR') or a.ShipperState = b.ShipperState)
			AND ((NOT case when a.RecipientState is null then 'null' else a.RecipientState end = 'PR' and isnull(b.RecipientState,'null') != 'PR') or a.RecipientState = b.RecipientState)
		AND a.RevThresholdAmt >= b.MinSpend
		AND a.RevThresholdAmt <= b.MaxSpend --revenue tier matches
		--Ground service uses these main service codes: 019 (OB), 417 (3P), 422 (RB), 137 (RM), 021 (IB), 142 (Call Tag), 018 (PRP), 804 (OB), 850 (3P) so these are the only ones that need to be built in the rate template
		AND (b.[GrdSvc] = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
		    or concat('0',b.[GrdSvc]) = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
			or b.[GrdSvc] is null 
			or b.[GrdSvc] = 'ALL') --ground service matches or ground service is null
		AND CASE 
			WHEN a.[ZoneJump] > ''
				THEN 1
			ELSE 0
			END = b.[ZJ] --zone jump matches. when the zone jump field in the prod table is non-blank, then it's a zone jump shipment
		AND (a.[ShipperCountry] = b.[ShipperCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[ShipperCountry] is null))
		AND (a.[RecipientCountry] = b.[RecipientCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[RecipientCountry] is null))
		--AND a.AccountCategory = b.AccountCategory --Original
		AND case when b.AccountCategory = 'ALL' then 9999 else b.AccountCategory end = case when b.AccountCategory = 'ALL' then 9999 else a.AccountCategory end		
	WHERE controlno = @ywControlNo 
		AND b.ChildId = a.ChildID
		AND b.[Discount] is not null
		AND b.[Rate] is null
		AND b.[MinSpend] is not null

	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractDiscountAmt] = round([PublishedRate] * [ContractDiscountPct] * - 1, 2)
	WHERE controlno = @ywControlNo 

	/* set the contract net min charges */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractMinNetCharge] = b.[MinNetCharge]
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON a.ChildID = b.ChildID
		AND cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (case when a.[Pkg] in ('03','04','13','23','33','43') then '01' when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = b.[ServicePackageCode] or case when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = concat('0',b.[ServicePackageCode]) )
		AND (case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = b.[ServiceTypeCode] or case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = concat('0',b.[ServiceTypeCode]) )--service matches
		AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL' or a.[Zone] = concat('0',b.[Zone]) or b.[Zone] = concat('0',a.[Zone])) -- zone matches or zone is null in the rate table which means it applies to all zones
		    AND ((NOT case when a.ShipperState is null then 'null' else a.Shipperstate end = 'PR' and isnull(b.ShipperState,'null') != 'PR') or a.ShipperState = b.ShipperState)
			AND ((NOT case when a.RecipientState is null then 'null' else a.RecipientState end = 'PR' and isnull(b.RecipientState,'null') != 'PR') or a.RecipientState = b.RecipientState)
		--Ground service uses these main service codes: 019 (OB), 417 (3P), 422 (RB), 137 (RM), 021 (IB), 142 (Call Tag), 018 (PRP), 804 (OB), 850 (3P) so these are the only ones that need to be built in the rate template
		AND (b.[GrdSvc] = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
		    or concat('0',b.[GrdSvc]) = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
			or b.[GrdSvc] is null 
			or b.[GrdSvc] = 'ALL') --ground service matches or ground service is null
		AND	CASE 
			WHEN a.[ZoneJump] > ''
				THEN 1
			ELSE 0
			END = b.[ZJ] --zone jump matches. when the zone jump field in the prod table is non-blank, then it's a zone jump shipment
		AND (a.[ShipperCountry] = b.[ShipperCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[ShipperCountry] is null))
		AND (a.[RecipientCountry] = b.[RecipientCountry] or ( (a.[ShipperCountry] != a.[RecipientCountry]) and b.[RecipientCountry] is null))
		AND b.[MinNetCharge] IS NOT NULL
		--AND a.AccountCategory = b.AccountCategory --Original
		AND case when b.AccountCategory = 'ALL' then 9999 else b.AccountCategory end = case when b.AccountCategory = 'ALL' then 9999 else a.AccountCategory end		
	WHERE controlno = @ywControlNo 
		AND b.ChildId = a.ChildID
		

	/* set the contract net rate amounts by simply adding the published rate and the discount (a negative number) */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractNetFreightCharge] = round([PublishedRate] + [ContractDiscountAmt], 2)
	WHERE controlno = @ywControlNo 
	AND [ContractDiscountAmt] is not null

	/* compare the above calculation to the minimum charge, if the minimum is bigger, then use the minimum */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractNetFreightCharge] = [ContractMinNetCharge]
	WHERE controlno = @ywControlNo 
		AND [ContractMinNetCharge] > [ContractNetFreightCharge]
		AND [ContractMinNetCharge] is not null

	/* use this if the contract rate shows a flat Rate instead of a discount */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractNetFreightCharge] = b.[Rate]
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON a.ChildID = b.ChildID
		AND cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (case when a.[Pkg] in ('03','04','13','23','33','43') then '01' when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = b.[ServicePackageCode] or case when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = concat('0',b.[ServicePackageCode]) )
		AND (case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = b.[ServiceTypeCode] or case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = concat('0',b.[ServiceTypeCode]) )--service matches
		AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL' or a.[Zone] = concat('0',b.[Zone]) or b.[Zone] = concat('0',a.[Zone])) -- zone matches or zone is null in the rate table which means it applies to all zones
		    AND ((NOT case when a.ShipperState is null then 'null' else a.Shipperstate end = 'PR' and isnull(b.ShipperState,'null') != 'PR') or a.ShipperState = b.ShipperState)
			AND ((NOT case when a.RecipientState is null then 'null' else a.RecipientState end = 'PR' and isnull(b.RecipientState,'null') != 'PR') or a.RecipientState = b.RecipientState)
		AND ((ceiling(cast([BillWt] AS FLOAT)) >= b.MinWeight AND ceiling(cast([BillWt] AS FLOAT)) <= b.MaxWeight) or (b.MinWeight is null and b.MaxWeight is null)) --weight matches or both weights are null
		--Ground service uses these main service codes: 019 (OB), 417 (3P), 422 (RB), 137 (RM), 021 (IB), 142 (Call Tag), 018 (PRP), 804 (OB), 850 (3P) so these are the only ones that need to be built in the rate template
		AND (b.[GrdSvc] = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
		    or concat('0',b.[GrdSvc]) = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
			or b.[GrdSvc] is null 
			or b.[GrdSvc] = 'ALL') --ground service matches or ground service is null
		AND CASE 
			WHEN a.[ZoneJump] > ''
				THEN 1
			ELSE 0
			END = b.[ZJ] --zone jump matches. when the zone jump field in the prod table is non-blank, then it's a zone jump shipment
		AND ( a.[ShipperCountry] = b.[ShipperCountry] or ((not a.[ShipperCountry] = a.[RecipientCountry]) and b.[ShipperCountry] is null) or (isnumeric(a.[Zone]) = 1 and b.[RecipientCountry] = a.[ShipperCountry]) )
		AND ( a.[RecipientCountry] = b.[RecipientCountry] or ((not a.[ShipperCountry] = a.[RecipientCountry]) and b.[RecipientCountry] is null) or (isnumeric(a.[Zone]) = 1 and b.[RecipientCountry] = a.[ShipperCountry]) )
		--AND a.AccountCategory = b.AccountCategory --Original
		AND case when b.AccountCategory = 'ALL' then 9999 else b.AccountCategory end = case when b.AccountCategory = 'ALL' then 9999 else a.AccountCategory end		
	WHERE controlno = @ywControlNo 
		AND b.ChildId = a.ChildID
		AND b.[Rate] is not null
		AND b.DiscountQual != 'Per Lb'

	/* second, look for contract rate multipliers */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractNetFreightCharge] = case when b.[Rate] * ceiling(cast([Billwt] as FLOAT)) > case when MinNetCharge is null then 0 else b.MinNetCharge end then b.[Rate] * ceiling(cast([Billwt] as FLOAT)) else case when b.MinNetCharge is null then 0 else b.MinNetCharge end end
	FROM tnl_rating.dbo.fdx_base_rate_audit a
	LEFT JOIN tnl_rating.dbo.fdx_rate_master b ON a.ChildID = b.ChildID
		AND cast(PickupDT AS DATETIME) >= b.EffectiveDate
		AND cast(PickupDT AS DATETIME) <= b.ExpirationDate
		AND (case when a.[Pkg] in ('03','04','13','23','33','43') then '01' when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = b.[ServicePackageCode] or case when a.[Pkg] = '02' and ([BillWt] > 2 or a.[ServiceTypeCode] = '06') then '01' else a.[Pkg] end = concat('0',b.[ServicePackageCode]) )
		AND (case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = b.[ServiceTypeCode] or case when a.[GrdSvc] in ('869','873') then '92' else a.[ServiceTypeCode] end = concat('0',b.[ServiceTypeCode]) )--service matches
		AND (a.[Zone] = b.[Zone] or b.[Zone] is null or b.[Zone] = 'ALL' or a.[Zone] = concat('0',b.[Zone]) or b.[Zone] = concat('0',a.[Zone])) -- zone matches or zone is null in the rate table which means it applies to all zones
		    AND ((NOT case when a.ShipperState is null then 'null' else a.Shipperstate end = 'PR' and isnull(b.ShipperState,'null') != 'PR') or a.ShipperState = b.ShipperState)
			AND ((NOT case when a.RecipientState is null then 'null' else a.RecipientState end = 'PR' and isnull(b.RecipientState,'null') != 'PR') or a.RecipientState = b.RecipientState)
		AND ((ceiling(cast([BillWt] AS FLOAT)) >= b.MinWeight AND ceiling(cast([BillWt] AS FLOAT)) <= b.MaxWeight) or (b.MinWeight is null and b.MaxWeight is null)) --weight matches or both weights are null
		--Ground service uses these main service codes: 019 (OB), 417 (3P), 422 (RB), 137 (RM), 021 (IB), 142 (Call Tag), 018 (PRP), 804 (OB), 850 (3P) so these are the only ones that need to be built in the rate template
		AND (b.[GrdSvc] = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
		    or concat('0',b.[GrdSvc]) = case when a.[GrdSvc] in ('158','159','418','487') then '417' when a.[GrdSvc] in ('340','342','423') then '422' when a.[GrdSvc] in ('131','133','136','139','140') then '137' when a.[GrdSvc] in ('020','315','873','869') then '021' when a.[GrdSvc] in ('015','016','150','151','302','303','358','359','361') then '019' when a.[GrdSvc] in ('143') then '142' when a.[GrdSvc] in ('018') then '018' when a.[GrdSvc] in ('800','824','883','895') then '804' when a.[GrdSvc] in ('851','863','887') then '850' else a.[GrdSvc] end
			or b.[GrdSvc] is null 
			or b.[GrdSvc] = 'ALL') --ground service matches or ground service is null
		AND CASE 
			WHEN a.[ZoneJump] > ''
				THEN 1
			ELSE 0
			END = b.[ZJ] --zone jump matches. when the zone jump field in the prod table is non-blank, then it's a zone jump shipment
		AND (a.[ShipperCountry] = b.[ShipperCountry] or ( (not a.[ShipperCountry] = a.[RecipientCountry]) and b.[ShipperCountry] is null))
		AND (a.[RecipientCountry] = b.[RecipientCountry] or ( (not a.[ShipperCountry] = a.[RecipientCountry]) and b.[RecipientCountry] is null))
		--AND a.AccountCategory = b.AccountCategory --Original
		AND case when b.AccountCategory = 'ALL' then 9999 else b.AccountCategory end = case when b.AccountCategory = 'ALL' then 9999 else a.AccountCategory end		
	WHERE controlno = @ywControlNo 
		AND b.ChildId = a.ChildID
		AND b.[Rate] is not null
		AND (b.[Notes] = 'Per Lb' or b.[DiscountQual] = 'Per Lb')


	/* For Freight Services, compare the net rates to the minimum charge if a minimum charge exists. If the minimum is bigger, then use the minimum */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractNetFreightCharge] = [ContractMinNetCharge]
	WHERE controlno = @ywControlNo 
		AND [ContractMinNetCharge] > [ContractNetFreightCharge]
		AND [ContractMinNetCharge] is not null
		AND ServiceTypeCode in ('39','70','80','83')

	/* set the potential error amount */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [PotentialError] = round([BilledNetFreightCharge] - [ContractNetFreightCharge], 2)
	WHERE controlno = @ywControlNo 

	/* This was useful before we added code to handle bundles on Oct 5, 2023. So now it's commented out *//* clear data on records that have a bundle number because bundled shipments throw off the audit */
/*	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [PublishedRate] = null
	,[ContractDiscountAmt] = null
	,[ContractDiscountPct] = null
	,[ContractMinNetCharge] = null
	,[ContractNetFreightCharge] = null
	,[PotentialError] = null
	WHERE controlno = @ywControlNo
	and [BundleNo] > ''
*/

	/* Clear data on records that were charged $0.00 or negative amounts. */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [PublishedRate] = 0
	,[ContractDiscountAmt] = null
	,[ContractDiscountPct] = null
	,[ContractMinNetCharge] = null
	,[ContractNetFreightCharge] = null
	,[PotentialError] = 0
	WHERE controlno = @ywControlNo 
	and BilledNetFreightCharge <= 0

	/* Clear data on records Puerto Rico Northbound/Southbound with multiple pieces, as FedEx is not transparent in their invoice data about the costing of these shipments. Also clear Ingram Micro (11528) Ground MWT, need to write code for that later */
	UPDATE tnl_rating.dbo.fdx_base_rate_audit
	SET [ContractDiscountAmt] = null
	,[ContractDiscountPct] = null
	,[ContractMinNetCharge] = null
	,[ContractNetFreightCharge] = null
	,[PotentialError] = 0
	WHERE controlno = @ywControlNo 
	and ( ((ShipperState = 'PR' or RecipientState = 'PR') and convert(float,Pcs) > 1) or (ChildID = '11528' and ServiceTypeCode = '92' and BundleNo > ''))

	EXEC [fdx_base_rate_audit_summary] @ywControlNo

	update [fdx_base_rate_audit]
	set israted = 1
	where controlno = @ywControlno 

	showResults:

	IF @ywShowResults = 1
	BEGIN
		SELECT fkey
			,PotentialError
			,*
		FROM fdx_base_rate_audit
		WHERE controlno = @ywControlNo
	END

	DROP TABLE IF EXISTS #fdx_base_rate_audit_bundles
END