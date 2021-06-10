# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

from typing import Any, Dict, Optional

from lisa import schema
from lisa.util import InitializableMixin, LisaException, subclasses
from lisa.util.logger import get_logger
from lisa.variable import VariableEntry


class Combinator(subclasses.BaseClassWithRunbookMixin, InitializableMixin):
    def __init__(self, runbook: schema.Combinator) -> None:
        super().__init__(runbook=runbook)
        self._log = get_logger("combinator", self.__class__.__name__)
        # return at least once, if it's empty
        self._is_first = True

    def fetch(
        self, current_variables: Dict[str, VariableEntry]
    ) -> Optional[Dict[str, VariableEntry]]:
        result: Optional[Dict[str, VariableEntry]] = None

        new_variables = self._next()

        if new_variables or self._is_first:
            result = current_variables.copy()
            if new_variables:
                result.update(new_variables)

        self._is_first = False
        return result

    def _initialize(self, *args: Any, **kwargs: Any) -> None:
        # if a combinator need long time initialization, it should be
        # implemented here.
        ...

    def _next(self) -> Optional[Dict[str, VariableEntry]]:
        raise NotImplementedError()

    def _validate_entry(self, entry: schema.Variable) -> None:
        if entry.file:
            raise LisaException(
                f"The value of combinator doesn't support file, "
                f"but got {entry.file}"
            )
        if not isinstance(entry.value, list):
            raise LisaException(
                f"The value of combinator must be a list, "
                f"but got {type(entry.value)}, value: {entry.value}"
            )
