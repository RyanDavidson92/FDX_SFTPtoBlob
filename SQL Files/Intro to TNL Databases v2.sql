--======================================================================================================================================================
--==               TNL_REPORTING
--==  This database houses the tables used to feed the ClearView portal, which is our tableau server where we keep client report decks
--======================================================================================================================================================

/*
The Shipment table houses shipment data and adjustment data (the [RecordType] column will show either "Parcel" or "Adjustment"). There is also basic info 
like sender/receiver addresses, base freight charges, fuel charge, resi charge, taxes, and total net charge but it does NOT have details regarding all the
individual accessorial fees like Delivery Area Surcharge, Additional Handling, Signature Required, Dangerous Goods, etc, etc.
It also has dimensions. And audit result data like Due Date, First Attempt Date, DeliveryDate, isLate
*/
select top(100) * from tnl_reporting.dbo.warehouse_shipment_history_vw

/*
The Lineitem table houses the accessorial detail for each shipment. Each shipment will have several rows in this table and each row has a different surcharge. It also
includes the base freight charge as its own row (for UPS there is one row for this charge, but for FedEx there is the Published rate and the Discount amount on different
rows, that's just how the carriers transmit the data to us. Since this table is so deep, we wanted it to be more narrow so it doesn't take up too much space in the
database, so it doesn't have all the same detail as the Shipment table. For example, it does NOT include dimensions.
*/
select top(100) * from tnl_reporting.dbo.warehouse_lineitem_history_vw

/*
The Invoice table is very slim and does NOT contain PLD (product level detail) like sender/receiver address, breakout of base rate/fuel/resi/etc, service types, ship dates, etc.
It is meant to hold the total Invoice amounts by client and account number. Our Shipment table and Lineitem table archive client data after 400 days by default (clients can pay 
to have longer retentions), but the Invoice table houses their total spend numbers for as long as they're a client.
*/
select top(100) * from tnl_reporting.dbo.warehouse_invoice_history_vw

/*
The Audit Approval table keeps data on the claims that ConData submits on behalf of clients that were approved, so we can show them how much we're saving them
*/
select top(100) * from tnl_reporting.dbo.Warehouse_Audit_Approval_History_vw

/*
The Company Parent table has all our client's ParentIDs
*/
select top(100) * from tnl_reporting.dbo.company_parent
/*
The Company Child table has all our client's ChildIDs. Usually different carriers get different ChildIDs but sometimes a single carrier like FDX or UPS will have multiple ChildIDs
within a single client. So Jacquie's client, Stryker, for example has many ChildIDs for FDX and many ChildIDs for UPS. And a separate ParentID for their Canadian volume
*/
select top(100) * from tnl_reporting.dbo.company_child
/*
The Account table houses all client account numbers and is where they are given names, group, subgroups, etc. This table has a group id which is linked to the company_account_group table.
*/
select top(100) * from tnl_reporting.dbo.company_account
select top(100) * from tnl_reporting.dbo.company_account_group

--======================================================================================================================================================
--==                   TNL_RATING
--==  This database houses the tables used for all rating activies like base rate auditing and accessorial rate auditing 
--==  I also use it as sort of a sandbox for analytic work that I need to do. For example, if a client wants a one-off ad
--==  hoc analysis, I will sometimes create tables in this database to use for that
--======================================================================================================================================================

/*
These tables house client rates. They are usually segmented by ChildID and EffectiveDate.
*/
select top(100) * from tnl_rating.dbo.fdx_rate_master
select top(100) * from tnl_rating.dbo.ups_rate_master
select top(100) * from tnl_rating.dbo.cpc_rate_master
select top(100) * from tnl_rating.dbo.pur_rate_master

--======================================================================================================================================================
--==                TNL_FDX, TNL_UPS, TNL_CPC, TNL_PUR
--==  These databases are where the raw invoice data goes when we receive them from the client. These databases are also used
--==  to complete the audit activies like tracking packages and determine ontime vs late status.
--======================================================================================================================================================

select top(100) * from tnl_fdx.dbo.fdx_ebill_prod --the main FedEx production table
select top(100) * from tnl_fdx.dbo.fdx_ebill_prod_fbo --the FedEx production table for data that comes from FBO (FedEx Billing Online).
select top(100) * from tnl_ups.dbo.ups_ebill_prod --the UPS production table
select top(100) * from tnl_pur.dbo.pur_ebill_prod --the PUR production table
select top(100) * from tnl_cpc.dbo.cpc_ebill_package --the CPC production table, not sure why it uses package instead of prod in its name


--======================================================================================================================================================
--==                  Additional Notes on the Databases
--======================================================================================================================================================

/*
 - For now, I wouldn't worry about these databases: TNL_ATS, TNL_DHL, TNL_REGIONAL
 - You won't have write access for now, so anytime you need to load rates, feel free to send me the queries and I will run them.
 - I would recommend trying to familiarize yourself with the tables above as best as you can. This will help you immensely in your work here. 
*/






--======================================================================================================================================================
--==                     Rate Auditing 
--======================================================================================================================================================

/*
ConData's auditing code in contained in the TNL_RATING database under Programmability -> Stored Procedures
All carriers need 2 separate Stored Procedures (sproc): (1) base rates and (2) accessorials

In general, the audit process looks like this:

	-> Raw invoice data gets loaded into ConData's databases and is assigned a Control Number
	-> The data in each Control Number goes through several steps to prepare it for reporting and auditing
	-> The Control Number will get passed to the rating engines based on carrier
	-> The rating engines function different depending on the carrier but the general process is:
		--> Only the relevant data is pulled from the raw invoice data tables and placed into the rate auditing results tables
			- usually accomplished through a loop/insert/populate sproc
		--> The stored procedures are executed 
			- Sprocs are designed to look at every shipment, identify its characteristics, and find the rate in the client rate tables that hold the contract rates
		--> If any differences are found between what the client was BILLED and what our tables show that their CONTRACT RATE is supposed to be
			then we identify that as a potential error and need to investigate why it happened and whether it is a TRUE error (could just be a bug in the sproc)
	-> Whenever true rate errors are confirmed, we notify the Sales Manager immediately and they notify the client.

*/

/*
Here are some of the rate audit sprocs, it is NECESSARY to be extremely familiar with this code
*/
tnl_rating.dbo.fdx_base_rate_audit_master
tnl_rating.dbo.ups_base_rate_audit_master



--======================================================================================================================================================
--==                     Investigating Potential Rate Errors
--======================================================================================================================================================

/*
	Whenever a potential error is found, there are two possible reasons
		- It is a true error and the Carrier billed the Client too much
		- There is a fault in the code and we did not correctly match the shipment to the contractual rate

		In order to help determine if the shipment was billed in error, here are some things to look at:

		- ACCOUNT NUMBER. One of the most common reasons for a client being billed incorrectly is that a specific account number was not
			loaded onto the correct discount plan in the Carrier's billing systems. Therefore you should look and see if matching shipments on other
			accounts are being billed correctly.
		- SHIP DATE. Make sure that the contract rates you're looking at are applicable for the date that the shipment was shipped. Tableau is a 
			very useful tool for researching what specific date a client started being billed new rates.
		- SHIPPING CODES. It's possible that there is a pattern of errors related to one or more of the codes used in Carrier shipping systems. For
			example, FedEx has a Pkg code field, a GrdSvc code field, a ServiceTypeCode field, etc, that all come into play when rating a shipment.
		- WEIGHT. Make sure you're looking at the correct weight of a shipment when finding the contract rate. Did you round it correctly, did you
			consider kg vs lb, did you run into a per-lb or per-kg multiplier. These are all questions that should be considered when trying to
			rate a shipment.
			- Dimensional Factor
		- OTHER. If the rating process looks like it is working correctly, and a shipment is still showing a billing error, then put the entire data
			set into Tableau and try to find a PATTERN of the error. It is almost NEVER the case that a client is billed in error randomly.
				- Did the error only occur after a VERY SPECIFIC date or during a SPECIFIC date range?
				- Did the error only occur on one account?
				- Is the error a constant dollar amount (all errors are exactly $2.17) or a constant % amount (all errors are exactly 3.50%)
				- Start with the billed rate and try to figure out how the Carrier landed at that amount. Did they use a certain % off the published rate
					and does that % off match all the other erroneous shipments? Did the carrier apply some minimum net rate to matches up with
					the rest of the erroneous shipments? Is is related to currency exchange? Did something change with the Carrier published rates or
					even their published rating methodology (i.e. when calculating fuel surcharge, the carriers now includes more accessorials then
					they used to, so fuel calculations need to be updated).
		-IS IT A MULTIPIECE ISSUE? PKG CODE ISSUE?

*/