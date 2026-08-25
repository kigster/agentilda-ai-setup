---
name: python-conventions
description: "Konstantin's Python conventions: four-space indentation, recent language features, `uv venv` for environments, a justfile to drive the project, Pydantic for data classes and PydanticAI for AI code, and Alembic or yoyo-migrations for schema changes. Use when writing or reviewing Python, or setting a Python project up."
---

## **Python**

Always use 4-spaces indentation.

Do aggressively utilize the most recent langauge features (Python 13.3+). Use `uv venv` to setup Python environment. Use `justfile` to control the project. Use `Pydantic` library always to define data classes, and use `PydanticAI` for the AI related code. Use `Alembic` when ORM is useful or for where its benefits outweight it's heavyness. Otherwise lean on (`yoyo-migrations`)[https://ollycope.com/software/yoyo/latest/] but ensure that the migration file naming starts with a timestamp that includes everything up to the second.

I use `uv venv` to set python up.
