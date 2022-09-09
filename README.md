# LibClassicSwingTimerAPI

There is no relevant WOW API to have an easily accessible state of the swing timer. This library fires custom EVENTS that can be used in other ADDONs to produce swing timer information.

## Usage example:

```
local SwingTimerLib = LibStub("LibClassicSwingTimerAPI", true)
if not SwingTimerLib then return end

local f = CreateFrame("Frame", nil)

local SwingTimerInfo = function(hand, unitGUID)
    return SwingTimerLib:SwingTimerInfo(hand, unitGUID)
end

local SwingTimerEventHandler = function(event, ...)
    return f[event](f, event, ...)
end

SwingTimerLib.RegisterCallback(f, "SWING_TIMER_START", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "SWING_TIMER_UPDATE", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "SWING_TIMER_CLIPPED", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "SWING_TIMER_PAUSED", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "SWING_TIMER_STOP", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "SWING_TIMER_DELTA", SwingTimerEventHandler)

```

## API EVENTS

### SWING_TIMER_START

Fired when a weapon or ranged swing starts.

| Property | Description |  
| ----------- | ----------- |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand that start to swing ("mainhand", "offhand" or "ranged") |
| unitGUID | string - the unit GUID |

### SWING_TIMER_UPDATE

Fired when weapon speed changes.

| Property | Description |  
| ----------- | ----------- |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand speed that update ("mainhand" or "offhand") |
| unitGUID | string - the unit GUID |

### SWING_TIMER_CLIPPED

Fired if a weapon swing is clipped by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| hand | string - The hand that is clipped "mainhand" or "offhand" |
| unitGUID | string - the unit GUID |

### SWING_TIMER_PAUSED

Fired if a weapon swing is paused by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| hand | string - The hand that is paused "mainhand" or "offhand" |
| unitGUID | string - the unit GUID |

### SWING_TIMER_STOP

Fired when a weapon or ranged swing ends.

| Property | Description |  
| ----------- | ----------- |
| hand | string - the hand that end a swing ("mainhand", "offhand" or "ranged") |
| unitGUID | string - the unit GUID |

### SWING_TIMER_DELTA

Fired when delta calculation between MH and OH update

| Property | Description |  
| ----------- | ----------- |
| swingDelta | number - Delta in seconds between MH and OH. |
| unitGUID | string - the unit GUID |

## API METHODS

### SwingTimerInfo(hand, unitGUID)

Returns the `hand`'s current swing state for the given unit GUID.

```
speed, expirationTime, lastSwing = SwingTimerInfo(hand)
```

- Arguments
    - hand
        - string - The hand to get information for ("mainhand", "offhand" or "ranged")
    - unitGUID
        - string - the unit GUID
- Returns
    - speed
        - number - weapon speed
    - expirationTime
        - number - end of swing relative to GetTime()
    - lastSwing
        - number - last swing relative to GetTime()
