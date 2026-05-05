package engine

import hm "core:container/handle_map"

hm_iter :: hm.iterator_make

hm_full :: proc "contextless" (m: $H/hm.Static_Handle_Map) -> bool { return hm.len(m) >= hm.cap(m) }
