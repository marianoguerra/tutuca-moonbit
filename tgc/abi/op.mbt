///|
pub fn Op::code(self : Op) -> Int {
  match self {
    OpWithField => 1
    OpHandleMessage => 2
    OpHandleIntent => 3
    OpCompute => 4
    OpWhen => 5
    OpEnrich => 6
    OpEnrichScope => 7
    OpGetProperty => 8
    OpSetProperty => 9
    OpSeqEntries => 10
    OpImplements => 11
    OpPersist => 12
    OpRestore => 13
    OpIdentity => 14
    OpDebug => 15
  }
}

///|
pub fn Op::of_code(code : Int) -> Op? {
  match code {
    1 => Some(OpWithField)
    2 => Some(OpHandleMessage)
    3 => Some(OpHandleIntent)
    4 => Some(OpCompute)
    5 => Some(OpWhen)
    6 => Some(OpEnrich)
    7 => Some(OpEnrichScope)
    8 => Some(OpGetProperty)
    9 => Some(OpSetProperty)
    10 => Some(OpSeqEntries)
    11 => Some(OpImplements)
    12 => Some(OpPersist)
    13 => Some(OpRestore)
    14 => Some(OpIdentity)
    15 => Some(OpDebug)
    _ => None
  }
}

///|
pub fn Op::name(self : Op) -> String {
  match self {
    OpWithField => "withField"
    OpHandleMessage => "handleMessage"
    OpHandleIntent => "handleIntent"
    OpCompute => "compute"
    OpWhen => "when"
    OpEnrich => "enrich"
    OpEnrichScope => "enrichScope"
    OpGetProperty => "getProperty"
    OpSetProperty => "setProperty"
    OpSeqEntries => "seqEntries"
    OpImplements => "implements"
    OpPersist => "persist"
    OpRestore => "restore"
    OpIdentity => "identity"
    OpDebug => "debug"
  }
}

///|
pub fn all_ops() -> Array[Op] {
  [
    OpWithField,
    OpHandleMessage,
    OpHandleIntent,
    OpCompute,
    OpWhen,
    OpEnrich,
    OpEnrichScope,
    OpGetProperty,
    OpSetProperty,
    OpSeqEntries,
    OpImplements,
    OpPersist,
    OpRestore,
    OpIdentity,
    OpDebug,
  ]
}
