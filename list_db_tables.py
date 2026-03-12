
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def list_tables():
    print("Tables in schema [administracion]:")
    with connection.cursor() as cur:
        cur.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'administracion'")
        for r in cur.fetchall():
            print(f"  {r[0]}")
            
    print("\nTables in schema [dbo] (related to config/orders):")
    with connection.cursor() as cur:
        cur.execute("SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME LIKE '%Config%'")
        for r in cur.fetchall():
            print(f"  {r[0]}")

if __name__ == "__main__":
    list_tables()
