import ./types
import ./surveyor

proc compare*(baseline, candidate: CaptainOutcome): VariantComparison =
  compareWithSurveyor(baseline, candidate)
