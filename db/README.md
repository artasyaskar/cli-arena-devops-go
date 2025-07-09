# Database Directory

This `db/` directory is intended for storing database-related files for the project. This could include:

- **Terraform State Files (Local):** If Terraform backends are configured to be local for certain parts of the project or for specific tasks, their `.tfstate` files might be directed here (though often they are kept within the relevant Terraform configuration directory or in a `.terraform` subdirectory).
- **Database Dumps/Backups:** SQL dumps, NoSQL database backups, or other data exports used for seeding databases or for restoration tasks.
- **Seed Data:** CSV files, JSON files, or scripts used to populate databases with initial data for the application or for specific test scenarios.
- **Example Configs:** Sample database configuration files (`*.conf`, `*.ini`, `*.yaml`) if the application or tasks require specific database setups. For example, `*.tfvars` files for Terraform database modules if they are not task-specific.
- **Migration Scripts:** SQL migration scripts or scripts for other database schema management tools.

## Task-Specific Data

Some tasks might generate or require their own specific data or state files. These are typically stored within the `tasks/<task-id>/resources/` or a task-specific `tasks/<task-id>/db/` directory to keep them self-contained.

This root `db/` directory is for more general or shared database assets. If no such general database assets are currently part of the project, this directory might only contain this README or a `.gitkeep` file.
