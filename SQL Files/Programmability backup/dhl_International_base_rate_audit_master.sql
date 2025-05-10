



------------ DHL Audit from scratch with fallback mechanism, seems to be working. 
----- This logic can be the basis for international DHL rating. 

WITH RankedRates AS (
    SELECT DISTINCT
        a.ChildID,
        a.TrackingNo,
        a.ControlNo,
        b.InvoiceDate,
        w.CodeDesc AS Service_Type,
        B.ServiceTypeCode,
        B.SenderCountryCode,
        B.ReceiverCountryCode,
        ISNULL(b.ChargeableWeight, b.BilledWeight) AS ChargeableWeight,
        b.BilledWeightUOM,c.CompanyChildCountry,
        o.zone AS OriginZone,
        CASE 
            WHEN c.CompanyChildCountry = B.ReceiverCountryCode AND c.CompanyChildCountry = b.SenderCountryCode THEN 'Dom'
            WHEN c.CompanyChildCountry = b.SenderCountryCode THEN 'Export'
            WHEN c.CompanyChildCountry = b.ReceiverCountryCode THEN 'Import'
			WHEN C.CompanyChildCountry<>B.SenderCountryCode AND C.CompanyChildCountry<>B.ReceiverCountryCode THEN '3C'  
            ELSE null
        END AS ShipmentType,
     --   COALESCE(m.Ratezone, '') AS RatezoneFor3C,--- 410 rows without this field. 
        a.ChargeAmt AS BilledRate,
        CASE
            WHEN r.RateType IN ('Flat LB', 'Flat', 'Flat KG') THEN r.Rate 
            WHEN r.RateType = 'Per LB (M)' THEN b.BilledWeight * r.Rate
            WHEN r.RateType = 'Per0.5KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 2 * r.Rate
            WHEN r.RateType = 'Per5.0KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 0.2 * r.Rate
            WHEN r.RateType = 'Per1.0KG_A' THEN r.BaseRateForMultiplier + (CEILING(b.BilledWeight) - r.MinWeight) * r.Rate
            WHEN r.RateType = 'Per0.5KG_M' THEN b.BilledWeight * 2 * r.Rate
            ELSE NULL 
        END AS ContractRate,
        ROUND(
            a.ChargeAmt - 
            CASE
                WHEN r.RateType IN ('Flat LB', 'Flat', 'Flat KG') THEN r.Rate 
                WHEN r.RateType = 'Per LB (M)' THEN b.BilledWeight * r.Rate
                WHEN r.RateType = 'Per0.5KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 2 * r.Rate
                WHEN r.RateType = 'Per5.0KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 0.2 * r.Rate
                WHEN r.RateType = 'Per1.0KG_A' THEN r.BaseRateForMultiplier + (CEILING(b.BilledWeight) - r.MinWeight) * r.Rate
                WHEN r.RateType = 'Per0.5KG_M' THEN b.BilledWeight * 2 * r.Rate
                ELSE NULL 
            END, 2
        ) AS PotentialError,
        RANK() OVER (
            PARTITION BY a.ChildID, a.TrackingNo,b.billedweight    --partitioning by weight might impact performance, the audit appears to be working without it. current run time in 2:20 for all records no constraints. 
            ORDER BY ABS(a.ChargeAmt - 
            CASE
                WHEN r.RateType IN ('Flat LB', 'Flat', 'Flat KG') THEN r.Rate 
                WHEN r.RateType = 'Per LB (M)' THEN b.BilledWeight * r.Rate
                WHEN r.RateType = 'Per0.5KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 2 * r.Rate
                WHEN r.RateType = 'Per5.0KG_A' THEN r.BaseRateForMultiplier + (b.BilledWeight - r.MinWeight) * 0.2 * r.Rate
                WHEN r.RateType = 'Per1.0KG_A' THEN r.BaseRateForMultiplier + (CEILING(b.BilledWeight) - r.MinWeight) * r.Rate
                WHEN r.RateType = 'Per0.5KG_M' THEN b.BilledWeight * 2 * r.Rate
                ELSE NULL 
            END) ASC
        ) AS RateRank
    FROM 
        [TNL_DHL].[dbo].[dhl_ebill_lineitem] AS a
    INNER JOIN 
        [TNL_DHL].[dbo].[dhl_ebill_package] AS b 
        ON a.ChildID = b.ChildID 
        AND a.ControlNo = b.ControlNo
        AND a.TrackingNo = b.TrackingNo
        AND a.ChargeCode = 'FREIGHT AMT'
    INNER JOIN 
        tnl_reporting.dbo.Warehouse_Dictionary W
        ON W.Carrier = 'DHL'
        AND a.ServiceTypeCode = W.Code
        AND W.Category = 'ServiceType'
    INNER JOIN 
        tnl_reporting.dbo.company_child C 
        ON a.ChildID = C.ChildID
    INNER JOIN 
        tnl_rating.dbo.dhl_country_zoning_table O 
        ON a.ChildID = O.ChildID
        AND c.CompanyChildCountry = O.RateCountry
        AND (
            CASE
                WHEN c.CompanyChildCountry = b.SenderCountryCode THEN 'Export'
                WHEN c.CompanyChildCountry = b.ReceiverCountryCode THEN 'Import'
				WHEN C.CompanyChildCountry<>B.SenderCountryCode AND C.CompanyChildCountry<>B.ReceiverCountryCode THEN '3C' 
				ELSE null
            END = O.ImportExport
        )
        AND B.SenderCountryCode = O.TargetCountry
    INNER JOIN 
        tnl_rating.dbo.dhl_country_zoning_table D 
        ON a.ChildID = D.ChildID
        AND c.CompanyChildCountry = D.RateCountry
        AND (
            CASE
                WHEN c.CompanyChildCountry = b.SenderCountryCode THEN 'Export'
                WHEN c.CompanyChildCountry = b.ReceiverCountryCode THEN 'Import'
				WHEN C.CompanyChildCountry<>B.SenderCountryCode AND C.CompanyChildCountry<>B.ReceiverCountryCode THEN '3C' 
				ELSE null
            END = D.ImportExport
        )
        AND B.ReceiverCountryCode = D.TargetCountry
    LEFT JOIN 
        tnl_rating.dbo.dhl_zone_conversion_matrix M
        ON a.ChildID = M.ChildID
        AND M.ImportExport = '3C'
        AND M.InternationalZone = O.Zone
        AND M.LocalZone = D.Zone
    INNER JOIN 
        tnl_rating.dbo.dhl_express_rate_master AS r
        ON B.ChildID = r.ChildID
        AND B.InvoiceDate > r.EffectiveDate 
        AND B.InvoiceDate <= r.ExpirationDate 
        AND b.BilledWeight > r.MinWeight
        AND b.BilledWeight <= r.MaxWeight
        AND r.Carrier = 'DHL'
        AND CASE 
            WHEN c.CompanyChildCountry = B.ReceiverCountryCode AND c.CompanyChildCountry = b.SenderCountryCode THEN 'Dom'
            WHEN c.CompanyChildCountry = b.SenderCountryCode THEN 'Export'
            WHEN c.CompanyChildCountry = b.ReceiverCountryCode THEN 'Import'
			WHEN C.CompanyChildCountry<>B.SenderCountryCode AND C.CompanyChildCountry<>B.ReceiverCountryCode THEN '3C' 
			ELSE null
        END = r.ExportImport
        AND w.CodeDesc = r.Service
        AND CASE 
            WHEN c.CompanyChildCountry = b.SenderCountryCode THEN D.Zone
            WHEN c.CompanyChildCountry = b.ReceiverCountryCode THEN O.Zone
			WHEN C.CompanyChildCountry<>B.SenderCountryCode AND C.CompanyChildCountry<>B.ReceiverCountryCode and b.ReceiverCountryCode = 'IL' then o.zone  ---- Specific to Applied materials. They are being charged on their IL rate card for companychildids that are DE. This increased the amount of errors from $599 to $2500 but reduced negative errors by ~ 2K.
            WHEN c.CompanyChildCountry <> b.SenderCountryCode AND c.CompanyChildCountry <> b.ReceiverCountryCode THEN M.Ratezone
            ELSE NULL 
        END = r.Zone
        AND (CASE WHEN w.CodeDesc IN ('CX', 'G', 'P', 'S', 'X', 'Y') THEN 'Non-Document' ELSE r.Package END = 'Non-Document')
		)


SELECT 
     *
FROM 
    RankedRates
where RateRank=1


 --AND CASE 
 --           WHEN CompanyChildCountry = RankedRates.ReceiverCountryCode AND CompanyChildCountry = RankedRates.SenderCountryCode THEN 'Dom'
 --           WHEN CompanyChildCountry = RankedRates.SenderCountryCode THEN 'Export'
 --           WHEN CompanyChildCountry = RankedRates.ReceiverCountryCode THEN 'Import'
 --           ELSE '3C'
 --       END = '3c'



 ---and RankedRates.childid = 12565 --- I think im done with 12565 for now, 3,117 returned out of 3,880 from production data. 

--and RankedRates.TrackingNo = '1001054471' --- heavy weight and gb/it/fr/ru example. 

--and RankedRates.TrackingNo = '2285777196'  --- 3c example
--and RankedRates.TrackingNo ='9907660081' --- 3c example with heavy weight , this shipment is using zone C from "DE Matrix DD 3rd city", I have loaded "DE Matrix TD 3RD City" using zone A. The joins are correct but not the zone tables. How should I distinguish between these two zone matrices? THIS IS NOW FIXED BY ADDING THE 3C ECONOMY ZONES.and RankedRates.TrackingNo = '1292326173' ---- import example
--and RankedRates.TrackingNo = '1001054471' --- heavy weight and gb/it/fr/ru example. 

--and RankedRates.TrackingNo = '2835327541' --- IE different weight calc example. 

--and RankedRates.TrackingNo = '1639662500'  -- W example, with heavy weight and 3C. --- This example returns one result that is super close to billed amt. unlike the other version without fallback mechanism. 


--and RankedRates.TrackingNo ='1381869230'  ---- This is being billed on the IL rate card import express. But it is a 3c shipment, this was fixed by creating a special case statement in the rate join for IL imports to be rated as 3c zones. 


--and RankedRates.trackingno = '1879970444'   ----- LOAD ISRAEL RATE CARD ZONES NOW. This is done, negative errors = $352, positive errors = $5,559. 15,637 shipments rated, $452K billed amount collected. 


--and RankedRates.TrackingNo = '2199828654' --- idk why its rating at 3 when it should be rating at zone 2 when both zones are loaded. I loaded GB zone 2 as 3C and this fixed it. this wasnt apart of the original rate card zone list. 
