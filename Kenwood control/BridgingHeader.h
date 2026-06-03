#ifndef BridgingHeader_h
#define BridgingHeader_h

#if __has_include("../ThirdParty/rnnoise/src/rnnoise.h")
#include "../ThirdParty/rnnoise/src/rnnoise.h"
#endif

#if __has_include("WDSPWrapper.h")
#include "WDSPWrapper.h"
#endif

#if __has_include("../ThirdParty/ft8_lib/ft8_bridge.h")
#include "../ThirdParty/ft8_lib/ft8_bridge.h"
#endif

#if __has_include("../ThirdParty/codec2/src/freedv_api.h")
#include "../ThirdParty/codec2/src/freedv_api.h"
#include "../ThirdParty/codec2/src/modem_stats.h"
#endif

// RADE (neural FreeDV voice) — clean public headers only. The opus/FARGAN
// internals stay hidden behind RADEFargan; rade_api.h is self-contained.
#if __has_include("../ThirdParty/radae/src/rade_api.h")
#include "../ThirdParty/radae/src/rade_api.h"
#endif

#if __has_include("RADEFargan.h")
#include "RADEFargan.h"
#endif

#endif /* BridgingHeader_h */
