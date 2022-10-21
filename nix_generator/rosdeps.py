import asyncio
import httpx
import itertools
import logging
import yaml

logging.basicConfig()
logger = logging.getLogger(__name__)


async def _fetch_rosdep_urls(urls):
    async with httpx.AsyncClient() as client:

        async def _fetch(url):
            result = await client.get(url, timeout=10.0, follow_redirects=True)
            data = yaml.safe_load(result.text)
            pairs = []
            for name, os_packages in data.items():
                if "nixos" in os_packages:
                    pairs.append((name, os_packages["nixos"]))
            logger.info(f"Loaded rosdep mappings: {url}")
            return pairs

        pairs = await asyncio.gather(*[_fetch(u) for u in urls])
        return dict(itertools.chain(*pairs))


def fetch_rosdeps(urls):
    return asyncio.run(_fetch_rosdep_urls(urls))
