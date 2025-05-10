
----- Create the ups base rate audit table which acts as the sink for the upsbaserateauditmaster sproc. 


CREATE TABLE TestDB.dbo.ups_base_rate_audit (
    LeadShipmentNumber           VARCHAR(50),
    ControlNo                    INT NOT NULL FOREIGN KEY REFERENCES TestDB.dbo.control_master(ControlNo),
    ChildID                      INT,
    BillToAccountNo              VARCHAR(50),
    InvoiceDt                    DATE,
    BillOptionCode               VARCHAR(10),
    ContainerType                VARCHAR(10),
    TransactionDate              DATE,
    PackageQuantity              INT,
    SenderCountry                VARCHAR(5),
    ReceiverCountry              VARCHAR(5),
    ChargeCategoryCode           VARCHAR(10),
    ChargeClassificationCode     VARCHAR(10),
    ChargeDescription            VARCHAR(100),
    Zone                         VARCHAR(10),
    BilledWeight                 NUMERIC(10,2),
    BilledWeightUnitOfMeasure    VARCHAR(5),
    NetAmount                    NUMERIC(10,2),
    ContractRate                 NUMERIC(10,2),
    PotentialError               NUMERIC(10,2),
    PublishedRate                NUMERIC(10,2),
    SenderState                  VARCHAR(5),
    ReceiverState                VARCHAR(5),
    InvoiceCurrencyCode          VARCHAR(5),
    isHundredweight              INT,
    isNextDayEarly               INT,
    Notes                        VARCHAR(255)
);



select * from ups_base_rate_audit