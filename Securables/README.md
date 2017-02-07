Change log and other information available at http://aka.ms/SQLInsights - SQL Swiss Army Knife Series

**Purpose:** Generates all database logins and their respective securables.

These are the options available:
- All users: EXEC usp_SecurCreation
- One user, All DBs: EXEC usp_SecurCreation '<User>'
- One user, One DB: EXEC usp_SecurCreation '<User>', '<DBName>'
- All users, One DB: EXEC usp_SecurCreation NULL, '<DBName>'

**Note:** Does not deal with CERTIFICATE_MAPPED_LOGIN and ASYMMETRIC_KEY_MAPPED_LOGIN types.