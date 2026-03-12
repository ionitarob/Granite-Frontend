
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def search_desc_keywords():
    keywords = ['HP PRO MINI', '27 IPS', 'CABLE CONVERSOR', 'MASTER >50GB']
    print(f"Searching for keywords in cotizaciones descriptions: {keywords}")
    
    with connection.cursor() as cur:
        for k in keywords:
            print(f"\n--- Results for %{k}% ---")
            query = "SELECT sku_config, description FROM [datapass].[administracion].[cotizaciones] WHERE description LIKE %s"
            cur.execute(query, [f"%{k}%"])
            rows = cur.fetchall()
            if not rows:
                print("No matches.")
            for r in rows:
                print(f"SKU={r[0]}, Desc={r[1]}")

if __name__ == "__main__":
    search_desc_keywords()
