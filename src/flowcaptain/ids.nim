import std/[strutils]

import ./types

const MaxSharedIdLen* = 160

proc kindName(kind: SharedIdKind): string =
  case kind
  of sikFlow: "flow"
  of sikRun: "run"
  of sikVariant: "variant"
  of sikNode: "node"
  of sikEdge: "edge"
  of sikArtifact: "artifact"
  of sikPolicy: "policy"

proc normalizeSharedId*(value: string): string =
  value.strip()

proc isSharedIdChar(ch: char): bool =
  ch.isAlphaNumeric or ch in {'-', '_', '.', ':'}

proc checkSharedId*(value: string; kind = sikFlow): SharedIdCheck =
  let normalized = value.normalizeSharedId()
  if normalized.len == 0:
    return SharedIdCheck(ok: false, normalized: normalized,
                         error: kind.kindName() & " id must not be empty")
  if normalized.len > MaxSharedIdLen:
    return SharedIdCheck(ok: false, normalized: normalized,
                         error: kind.kindName() & " id is too long")
  for ch in normalized:
    if not ch.isSharedIdChar():
      return SharedIdCheck(ok: false, normalized: normalized,
                           error: kind.kindName() &
                             " id contains an invalid character: " & $ch)
  SharedIdCheck(ok: true, normalized: normalized, error: "")

proc isValidSharedId*(value: string; kind = sikFlow): bool =
  value.checkSharedId(kind).ok
