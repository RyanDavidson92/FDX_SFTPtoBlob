# FDX_SFTPtoBlob

FedEx pipeline for SFTP ingestion into a SQL Data Warehouse.

## 🔧 Purpose

This repository automates the ingestion of FedEx client files from a secure SFTP server into an Azure-based SQL data warehouse. It supports:

- Client-specific credentials and folder structures
- Automatic ControlNo and ClientID tracking
- Raw and transformed uploads to Azure Blob Storage
- Duplicate prevention and metadata logging

## 🚀 Features

- ✅ FedEx-specific V6 ingestion logic
- ✅ Azure Blob Storage integration
- ✅ SQL Server connection via `pyodbc`
- ✅ ControlNo tracking with `SCOPE_IDENTITY()`
- ✅ Duplicate file prevention with SHA256 hash
- ✅ Environment-specific configuration via `.env`


