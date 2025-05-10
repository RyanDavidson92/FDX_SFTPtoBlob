
  
  select * from Company_Parent
  
  
  INSERT INTO [dbo].[Company_Parent] (
    ParentID,
    ChildID,
    CompanyName,
    Carrier,
    POC_Name,
    POC_Email,
    POC_Phone,
    CreateDate
)
VALUES (
    2,                                      -- ParentID
    12661,                                  -- New ChildID
    'Client C - Test',              -- CompanyName
    'UPS',                                  -- Carrier
    'John Tester',                          -- POC_Name
    'john.tester@example.com',              -- POC_Email
    '555-987-6543',                         -- POC_Phone
    GETDATE()                               -- CreateDate
);





--delete from Company_Parent where ChildID = 12661