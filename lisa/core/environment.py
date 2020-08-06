from __future__ import annotations

import copy
from typing import TYPE_CHECKING, Dict, List, Optional, cast

from lisa.core.nodeFactory import NodeFactory
from lisa.util import constants
from lisa.util.logger import log

if TYPE_CHECKING:
    from lisa.core.platform import Platform

    from .node import Node


class Environment(object):
    def __init__(self) -> None:
        self.nodes: List[Node] = []
        self.name: Optional[str] = ""
        self.platform: Optional[Platform] = None
        self.isReady: bool = False
        self.spec: Optional[Dict[str, object]] = None

    @staticmethod
    def loadEnvironment(config: Dict[str, object]) -> Environment:
        environment = Environment()
        spec = copy.deepcopy(config)

        environment.name = cast(Optional[str], spec.get(constants.NAME))

        has_default_node = False
        nodes_spec = []
        nodes_config = cast(
            List[Dict[str, object]], spec.get(constants.ENVIRONMENTS_NODES)
        )
        if nodes_config is not None:
            for node_config in nodes_config:
                node = NodeFactory.createNodeFromConfig(node_config)
                if node is not None:
                    environment.nodes.append(node)
                else:
                    nodes_spec.append(node_config)

                is_default = cast(Optional[bool], node_config.get(constants.IS_DEFAULT))
                has_default_node = environment._validateSingleDefault(
                    has_default_node, is_default
                )

        # validate template and node not appear together
        nodes_template = spec.get(constants.ENVIRONMENTS_TEMPLATE)
        if nodes_template is not None:
            nodes_template = cast(List[Dict[str, object]], nodes_template)
            for item in nodes_template:
                node_count = cast(
                    Optional[int], item.get(constants.ENVIRONMENTS_TEMPLATE_NODE_COUNT)
                )
                if node_count is None:
                    node_count = 1
                else:
                    del item[constants.ENVIRONMENTS_TEMPLATE_NODE_COUNT]

                is_default = cast(Optional[bool], item.get(constants.IS_DEFAULT))
                has_default_node = environment._validateSingleDefault(
                    has_default_node, is_default
                )
                for index in range(node_count):
                    copied_item = copy.deepcopy(item)
                    # only one default node for template also
                    if is_default is True and index > 0:
                        del copied_item[constants.IS_DEFAULT]
                    nodes_spec.append(copied_item)
            del spec[constants.ENVIRONMENTS_TEMPLATE]

        if len(nodes_spec) == 0 and len(environment.nodes) == 0:
            raise Exception("not found any node in environment")

        spec[constants.ENVIRONMENTS_NODES] = nodes_spec

        environment.spec = spec
        log.debug("environment spec is %s", environment.spec)
        return environment

    @property
    def defaultNode(self) -> Node:
        default = None
        if self.nodes is not None:
            for node in self.nodes:
                if node.isDefault is True:
                    default = node
                    break
            if default is None:
                default = self.nodes[0]
        if default is None:
            raise Exception("No node found in current environment")
        return default

    def getNodeByName(self, name: str, throwError: bool = True) -> Optional[Node]:
        found = None
        if self.nodes is not None:
            for node in self.nodes:
                if node.name == name:
                    found = node
                    break
            if throwError:
                raise Exception("cannot find node %s" % (name))
        else:
            if throwError:
                raise Exception("nodes shouldn't be None when call getNodeByName")
        return found

    def getNodeByIndex(self, index: int, throwError: bool = True) -> Optional[Node]:
        found = None
        if self.nodes is not None:
            if len(self.nodes) > index:
                found = self.nodes[index]
        elif throwError:
            raise Exception("nodes shouldn't be None when call getNodeByIndex")
        return found

    def setPlatform(self, platform: Platform) -> None:
        self.platform = platform

    def _validateSingleDefault(
        self, has_default: bool, is_default: Optional[bool]
    ) -> bool:
        if is_default is True:
            if has_default is True:
                raise Exception("only one node can set isDefault to True")
            has_default = True
        return has_default

    def cleanup(self) -> None:
        for node in self.nodes:
            node.cleanup()
