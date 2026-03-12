
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection

def check_all_tipos(idnbr):
    with connection.cursor() as cur:
        cur.execute("SELECT SKU, TIPO FROM dbo.tbl_ConfigOrderLine WHERE parent_idnbr = %s", (idnbr,))
        rows = cur.fetchall()
        print(f"Order IDNBR: {idnbr}")
        for r in rows:
            print(f"SKU: {r[0]}, TIPO: {r[1]}")

if __name__ == "__main__":
    check_all_tipos(43774)
