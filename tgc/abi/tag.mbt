///|
pub fn Tag::code(self : Tag) -> Int {
  match self {
    TagNull => 0
    TagBool => 1
    TagNum => 2
    TagInt => 3
    TagStr => 4
    TagBin => 5
    TagInstant => 6
    TagList => 7
    TagMap => 8
    TagFunc => 9
    TagComp => 10
    TagExt => 11
  }
}

///|
pub fn Tag::of_code(code : Int) -> Tag? {
  match code {
    0 => Some(TagNull)
    1 => Some(TagBool)
    2 => Some(TagNum)
    3 => Some(TagInt)
    4 => Some(TagStr)
    5 => Some(TagBin)
    6 => Some(TagInstant)
    7 => Some(TagList)
    8 => Some(TagMap)
    9 => Some(TagFunc)
    10 => Some(TagComp)
    11 => Some(TagExt)
    _ => None
  }
}

///|
pub fn Tag::type_name(self : Tag) -> String {
  match self {
    TagNull => "tg_val"
    TagBool => "tg_bool"
    TagNum => "tg_num"
    TagInt => "tg_int"
    TagStr => "tg_str"
    TagBin => "tg_bin"
    TagInstant => "tg_instant"
    TagList => "tg_list"
    TagMap => "tg_map"
    TagFunc => "tg_func"
    TagComp => "tg_comp"
    TagExt => "tg_ext"
  }
}

///|
pub fn all_tags() -> Array[Tag] {
  [
    TagNull,
    TagBool,
    TagNum,
    TagInt,
    TagStr,
    TagBin,
    TagInstant,
    TagList,
    TagMap,
    TagFunc,
    TagComp,
    TagExt,
  ]
}
