from typing import Dict, List, Optional, Type, cast

from singleton_decorator import singleton

from lisa.util import constants
from lisa.util.logger import log

from .platform import Platform


@singleton
class PlatformFactory:
    def __init__(self) -> None:
        self.platforms: Dict[str, Platform] = dict()

    def registerPlatform(self, platform: Type[Platform]) -> None:
        platform_type = platform.platformType().lower()
        if self.platforms.get(platform_type) is None:
            self.platforms[platform_type] = platform()
        else:
            raise Exception("platform '%s' exists, cannot be registered again")

    def initializePlatform(self, config: Optional[List[Dict[str, object]]]) -> Platform:

        if config is None:
            raise Exception("cannot find platform")
        # we may extend it later to support multiple platforms
        platform_count = len(config)
        if platform_count != 1:
            raise Exception("There must be 1 and only 1 platform")
        platform_type = cast(Optional[str], config[0].get("type"))
        if platform_type is None:
            raise Exception("type of platfrom shouldn't be None")

        self._buildFactory()
        log.debug(
            "registered platforms [%s]",
            ", ".join([name for name in self.platforms.keys()]),
        )

        platform = self.platforms.get(platform_type.lower())
        if platform is None:
            raise Exception("cannot find platform type '%s'" % platform_type)
        log.info("activated platform '%s'", platform_type)

        platform.config(constants.CONFIG_CONFIG, config[0])
        return platform

    def _buildFactory(self) -> None:
        for sub_class in Platform.__subclasses__():
            self.registerPlatform(sub_class)
