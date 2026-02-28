from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Dict, List, Optional


class GroqImportError(ImportError):
    """Raised when the groq package is not installed but required."""


def _load_float_env(name: str, default: Optional[float]) -> Optional[float]:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    try:
        return float(raw)
    except ValueError:
        return default


def _load_int_env(name: str, default: Optional[int]) -> Optional[int]:
    raw = os.getenv(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


@dataclass
class GroqConfig:
    api_key: Optional[str] = None
    model: str = os.getenv("GROQ_MODEL", "llama-3.3-70b-versatile")
    temperature: Optional[float] = _load_float_env("LLM_TEMPERATURE", 0.2)
    max_tokens: Optional[int] = _load_int_env("LLM_MAX_TOKENS", None)


class GroqLLMClient:
    """
    Thin wrapper around Groq's Python client.

    This keeps all Groq-specific code in one place so the rest of the
    application depends only on this abstraction.
    """

    def __init__(self, config: Optional[GroqConfig] = None) -> None:
        try:
            from groq import Groq  # type: ignore
        except Exception as exc:  # pragma: no cover - only hit when groq missing
            raise GroqImportError(
                "The 'groq' package is required for GroqLLMClient. "
                "Install it with: pip install groq"
            ) from exc

        self._GroqClass = Groq
        self.config = config or GroqConfig()

        # Groq client will read GROQ_API_KEY from env if api_key is not passed explicitly.
        if self.config.api_key:
            self._client = Groq(api_key=self.config.api_key)
        else:
            self._client = Groq()

    @property
    def model(self) -> str:
        return self.config.model

    def chat_completion(
        self,
        messages: List[Dict[str, Any]],
        model: Optional[str] = None,
        temperature: Optional[float] = None,
        max_tokens: Optional[int] = None,
        **kwargs: Any,
    ) -> str:
        """
        Perform a single non-streaming chat completion and return the text.

        Parameters
        ----------
        messages:
            List of chat messages in Groq's format:
            [{ "role": "system"|"user"|"assistant", "content": "..." }, ...]
        model:
            Optional override for the model name.
        temperature:
            Optional override for sampling temperature.
        max_tokens:
            Optional override for max tokens in the response.
        kwargs:
            Additional arguments forwarded to Groq (e.g. top_p).
        """
        chosen_model = model or self.config.model
        chosen_temp = self.config.temperature if temperature is None else temperature
        chosen_max_tokens = self.config.max_tokens if max_tokens is None else max_tokens

        params: Dict[str, Any] = {
            "model": chosen_model,
            "messages": messages,
        }
        if chosen_temp is not None:
            params["temperature"] = chosen_temp
        if chosen_max_tokens is not None:
            params["max_tokens"] = chosen_max_tokens

        params.update(kwargs)

        completion = self._client.chat.completions.create(**params)
        choice = completion.choices[0]
        return choice.message.content or ""

