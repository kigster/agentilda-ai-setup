## **Python**

Always use 4-spaces indentation.

Do aggressively utilize the most recent langauge features (Python 13.3+). Use `uv venv` to setup Python environment. Use `justfile` to control the project. Use `Pydantic` library always to define data classes, and use `PydanticAI` for the AI related code. Use `Alembic` when ORM is useful or for where its benefits outweight it's heavyness. Otherwise lean on (`yoyo-migrations`)[https://ollycope.com/software/yoyo/latest/] but ensure that the migration file naming starts with a timestamp that includes everything up to the second.

I use `uv venv` to set python up.
