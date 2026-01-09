    # Django Channels consumer for broadcasting today's AMZ grading count
# Place this file in your Django app (e.g., myapp/consumers.py) and wire it into your routing.

import json
import logging
from channels.generic.websocket import AsyncWebsocketConsumer

logger = logging.getLogger(__name__)

class AmzTodayConsumer(AsyncWebsocketConsumer):
    """
    WebSocket consumer that joins the "amz_today" group and forwards events to clients.

    Behavior:
    - On connect(): accept and immediately send the current today's count using the message
      {"type": "amz.today", "count": N}
    - On receiving group events, forward as JSON to connected clients and log the event for debugging.

    Notes:
    - This code assumes you have a way to obtain the current "today" count when users connect (replace get_today_count()).
    - Add this consumer to your routing (e.g., in routing.py:
        from django.urls import re_path
        from .consumers import AmzTodayConsumer
        websocket_urlpatterns = [ re_path(r"ws/amz/today$", AmzTodayConsumer.as_asgi()), ]
    - Ensure Channels and channel_redis are configured and Redis is available for the channel layer.
    """

    async def connect(self):
        self.group_name = 'amz_today'
        # Accept the connection
        await self.accept()
        # Add to group
        await self.channel_layer.group_add(self.group_name, self.channel_name)

        # Get the initial today's count (you must implement this retrieval)
        try:
            count = await self.get_today_count()
        except Exception:
            count = None

        # Send initial payload
        payload = {"type": "amz.today", "count": count if count is not None else 0}
        await self.send_json(payload)
        logger.info(f"AmzTodayConsumer: client connected {self.channel_name}, sent initial {payload}")

    async def disconnect(self, close_code):
        try:
            await self.channel_layer.group_discard(self.group_name, self.channel_name)
        except Exception:
            logger.exception("Failed to discard from group")

    async def receive(self, text_data=None, bytes_data=None):
        # This consumer is server->client only. Optionally handle client messages here.
        logger.debug(f"AmzTodayConsumer received from client: {text_data}")

    async def amz_today_event(self, event):
        """Handler for events sent to the 'amz_today' group.
        Expected event format: {'type': 'amz_today_event', 'count': N}
        We'll forward to the client as {"type":"amz.today","count":N}
        """
        try:
            count = event.get('count')
            payload = {"type": "amz.today", "count": count}
            await self.send_json(payload)
            logger.info(f"AmzTodayConsumer: forwarded event to {self.channel_name}: {payload}")
        except Exception:
            logger.exception("Failed to forward amz_today event")

    async def get_today_count(self):
        """Placeholder async method. Replace with your logic to compute today's count.
        For example, query the DB or a cache value. Return an int.
        """
        # TODO: implement actual retrieval. For now, return 0.
        return 0
