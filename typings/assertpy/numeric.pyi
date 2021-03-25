from typing import Any

from .assertpy import AssertionBuilder

__tracebackhide__: bool

class NumericMixin:
    def is_zero(self) -> AssertionBuilder: ...
    def is_not_zero(self) -> AssertionBuilder: ...
    def is_nan(self) -> AssertionBuilder: ...
    def is_not_nan(self) -> AssertionBuilder: ...
    def is_inf(self) -> AssertionBuilder: ...
    def is_not_inf(self) -> AssertionBuilder: ...
    def is_greater_than(self, other: Any) -> AssertionBuilder: ...
    def is_greater_than_or_equal_to(self, other: Any) -> AssertionBuilder: ...
    def is_less_than(self, other: Any) -> AssertionBuilder: ...
    def is_less_than_or_equal_to(self, other: Any) -> AssertionBuilder: ...
    def is_positive(self) -> AssertionBuilder: ...
    def is_negative(self) -> AssertionBuilder: ...
    def is_between(self, low: Any, high: Any) -> AssertionBuilder: ...
    def is_not_between(self, low: Any, high: Any) -> AssertionBuilder: ...
    def is_close_to(self, other: Any, tolerance: Any) -> AssertionBuilder: ...
    def is_not_close_to(self, other: Any, tolerance: Any) -> AssertionBuilder: ...