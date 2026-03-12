
import os
import django
import sys

# Setup django
# Backend path is c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend
# We are currently in the frontend directory
backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def check_skus(idnbr):
    skus = []
    with connection.cursor() as cursor:
        cursor.execute("SELECT SKU, DESCRIP1, TIPO FROM dbo.tbl_ConfigOrderLine WHERE parent_idnbr = %s", [idnbr])
        rows = cursor.fetchall()
        print(f"Order {idnbr} Lines:")
        for row in rows:
            sku_val = row[0]
            print(f"  SKU: '{sku_val}', TIPO: '{row[2]}', Desc: {row[1]}")
            skus.append(sku_val)
            
    print("\nChecking against cotizaciones (Exact match):")
    for sku in skus:
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT id, sku_config, sku_hp, sku_lenovo, description 
                FROM [datapass].[administracion].[cotizaciones] 
                WHERE sku_config = %s OR sku_hp = %s OR sku_lenovo = %s
            """, [sku, sku, sku])
            matches = cursor.fetchall()
            if not matches:
                print(f"  SKU '{sku}': NO EXACT MATCH FOUND")
            for m in matches:
                print(f"  SKU '{sku}': MATCH FOUND! ID={m[0]}, Config={m[1]}, HP={m[2]}, Lenovo={m[3]}, Desc={m[4]}")

    print("\nChecking against cotizaciones (LIKE match / Trimmed):")
    for sku in skus:
        sku_clean = sku.strip()
        with connection.cursor() as cursor:
            cursor.execute("""
                SELECT id, sku_config, sku_hp, sku_lenovo, description 
                FROM [datapass].[administracion].[cotizaciones] 
                WHERE LTRIM(RTRIM(sku_config)) = %s OR LTRIM(RTRIM(sku_hp)) = %s OR LTRIM(RTRIM(sku_lenovo)) = %s
            """, [sku_clean, sku_clean, sku_clean])
            matches = cursor.fetchall()
            if matches and not any(match[1] == sku or match[2] == sku or match[3] == sku for match in matches):
                print(f"  SKU '{sku}': FOUND WITH TRIM/LIKE! Potential whitespace issue.")
            elif matches:
                 print(f"  SKU '{sku}': FOUND WITH TRIM/LIKE (already found or whitespace confirmed hit).")
            else:
                print(f"  SKU '{sku}': STILL NO MATCH FOUND")

if __name__ == "__main__":
    check_skus(43771)
