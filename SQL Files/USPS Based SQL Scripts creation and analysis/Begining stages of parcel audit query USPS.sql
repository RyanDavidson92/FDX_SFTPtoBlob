

----- Begining stages of parcel audit query USPS


;WITH RankedMatches AS (
        SELECT
            p.childid,
            p.TrackingNumber AS [Tracking number],
            
            p.controlno, 
            p.ShipDate,
            p.BilledWeight_LB,
            p.ServiceLevel AS [Service], 
            p.length, p.width, p.height,
            p.Zone AS [Billed_Zone], 
            ((p.length * p.width * p.height)/1728.0) AS [cubic feet],r.PackageType AS [Package Indicator],
            r.Tier,
            ROW_NUMBER() OVER (
                PARTITION BY p.TrackingNumber,p.controlno
                ORDER BY ABS(p.packagecharge - r.Rate) ASC
            ) AS RN,
            p.PackageCharge AS Billed_Amount,		
            r.Rate AS [Contract_Rate],
            CASE 
                WHEN ROUND((p.PackageCharge - r.Rate), 2) IN (0.01, -0.01)
                    THEN 0 
                ELSE ROUND((p.PackageCharge - r.Rate), 2) 
            END AS [PotentialError]
        FROM TestDB.dbo.usps_ebill_prod AS p
        LEFT JOIN TestDB.dbo.usps_rate_master AS r ON  (
        (
            
			 -- Match for NonCubic
			-----"Cubic prices are not based on weight, but are charged based on zone and the mailpiece's cubic measurement..." ---- IN CASE YOU ARE WONDERING WHY WEIGHT BASED JOIN IS NOT HERE. 
			----- SROUCE : https://pe.usps.com/text/dmm300/223.htm

            r.PackageType = 'NonCubic'
            AND r.ServiceType = p.ServiceLevel
            AND r.ChildID = p.ChildID
            AND r.Zone = p.Zone
            AND p.ShipDate BETWEEN r.EffectiveDate AND r.ExpirationDate
        )
        OR (
            r.Billed_Weight = 0 AND r.PackageType = 
                CASE 
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.10 THEN 'Cubic Tier 1 (0.00 - 0.10)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.20 THEN 'Cubic Tier 2 (0.10 - 0.20)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.30 THEN 'Cubic Tier 3 (0.20 - 0.30)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.40 THEN 'Cubic Tier 4 (0.30 - 0.40)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.50 THEN 'Cubic Tier 5 (0.40 - 0.50)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.60 THEN 'Cubic Tier 6 (0.50 - 0.60)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.70 THEN 'Cubic Tier 7 (0.60 - 0.70)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.80 THEN 'Cubic Tier 8 (0.70 - 0.80)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 0.90 THEN 'Cubic Tier 9 (0.80 - 0.90)'
                    WHEN ((p.length * p.width * p.height)/1728.0) <= 1.00 THEN 'Cubic Tier 10 (0.90 - 1.00)'
                END
        )
        OR (
            -- packages (weight 0, PackageIndicator matches these types)
            r.Billed_Weight = 0
            AND r.PackageType IN (
                'Flat-Rate Envelope',
                'Large Flat-Rate Box',
                'Legal Flat-Rate Envelope',
                'Medium Flat-Rate Box',
                'NonCubic',
                'Padded Flat-Rate Envelope',
                'Small Flat-Rate Box'
            )
        )
    )
        AND p.ServiceLevel = r.ServiceType
        AND p.ChildID = r.ChildID
        AND p.ShipDate >= r.Effectivedate 
        AND p.ShipDate <= r.Expirationdate
        AND p.zone = r.zone)
      
     


select * from RankedMatches


/*
SELECT 
    FORMAT(COUNT(*), 'N0') AS [Shipment Count],FORMAT(
        100.0 * SUM(CASE WHEN Billed_Amount IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*),
        'N2'
    ) + '%' AS [% Rated],
    FORMAT(
        100.0 * SUM(CASE WHEN Billed_Amount IS NULL THEN 1 ELSE 0 END) / COUNT(*),
        'N2'
    ) + '%' AS [% Unrated],
    FORMAT(SUM(Billed_Amount), 'C') AS [ChargeRate],
    FORMAT(SUM(Contract_Rate), 'C') AS [Contract Rate],
    FORMAT(SUM(potentialerror), 'C') AS [TotalError]
    
FROM RankedMatches
WHERE RN = 1;

*/