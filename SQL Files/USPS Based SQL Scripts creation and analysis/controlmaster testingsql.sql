


select * from control_master


-- Step 2: Delete parent records ## use delete vs truncate due to foreign key constraints, truncate doesnt allow this. 
DELETE FROM control_master;

-- Step 3: Reseed ControlNo to 1000
DBCC CHECKIDENT ('control_master', RESEED, 1000);

DELETE FROM control_master WHERE ControlNo = 1005;


select * from TestDB.DBO.usps_ebill_prod where ControlNo = 1005





sp_help control_master;
