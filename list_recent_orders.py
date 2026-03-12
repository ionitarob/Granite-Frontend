
import os
import django
import sys

backend_path = r'c:\Users\rmaglan\Documents\CTool Granite\Granite-Backend\django_backend'
sys.path.append(backend_path)
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'django_backend.settings')
django.setup()

from django.db import connection
from apps.orderops.models import AgentOrder

def list_orders():
    orders = AgentOrder.objects.all().order_by('-idnbr')[:10]
    print("Recent Orders in agent_orders table:")
    for o in orders:
        print(f"  IDNBR: {o.idnbr}, OrderNbr: {o.order_nbr}, Customer: {o.customer}")
        
    # Check specifically for the one the user mentioned
    target = '291910811'
    o_target = AgentOrder.objects.filter(order_nbr=target).first()
    if o_target:
        print(f"\nFOUND BY order_nbr '{target}': IDNBR={o_target.idnbr}")
    else:
        print(f"\nNOT FOUND BY order_nbr '{target}'")
        
    o_idnbr = AgentOrder.objects.filter(idnbr=target).first()
    if o_idnbr:
        print(f"FOUND BY idnbr '{target}': OrderNbr={o_idnbr.order_nbr}")
    else:
        print(f"NOT FOUND BY idnbr '{target}'")

if __name__ == "__main__":
    list_orders()
