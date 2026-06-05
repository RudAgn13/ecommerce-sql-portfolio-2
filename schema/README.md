## Schema

**Database:** PostgreSQL 15  
**Tables:** 10  
**Sample rows:** ~860 (representative seed — see data generation notes for full scale)

### How to run
Paste `create_tables_and_seed.sql` into [dbfiddle.uk](https://dbfiddle.uk) (select PostgreSQL 15)
or run locally:
```bash
psql -U your_user -d your_db -f schema/create_tables_and_seed.sql
```
