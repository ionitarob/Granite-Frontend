
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def count_unmapped_svcs():
    sql = """
        SELECT COUNT(*) 
        FROM dbo.tbl_ConfigOrderLine l 
        WHERE (DESCRIP1 LIKE '%SVCS%' OR DESCRIP2 LIKE '%SVCS%') 
          AND NOT EXISTS (
              SELECT 1 FROM [datapass].[administracion].[cotizaciones] c 
              WHERE l.SKU = c.sku_config OR l.SKU = c.sku_hp OR l.SKU = c.sku_lenovo
          )
    """
    with connection.cursor() as cur:
        cur.execute(sql)
        count = cur.fetchone()[0]
        print(f"Total unmapped lines with 'SVCS' in description: {count}")

if __name__ == "__main__":
    count_unmapped_svcs()
