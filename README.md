# LibClassicSwingTimerAPI

There is no relevant WOW API to have an easily accessible state of the swing timer. This library fires custom EVENTS that can be used in other ADDONs to produce swing timer information.

## Usage example:

```
local SwingTimerLib = LibStub("LibClassicSwingTimerAPI", true)
if not SwingTimerLib then return end

local f = CreateFrame("Frame", nil)

local UnitSwingTimerInfo = function(unitId, hand)
    return SwingTimerLib:UnitSwingTimerInfo(unitId, hand)
end

local SwingTimerEventHandler = function(event, ...)
    return f[event](f, event, ...)
end

SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_INFO_INITIALIZED", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_START", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_UPDATE", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_CLIPPED", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_PAUSED", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_STOP", SwingTimerEventHandler)
SwingTimerLib.RegisterCallback(f, "UNIT_SWING_TIMER_DELTA", SwingTimerEventHandler)

```
## API EVENTS

### UNIT_SWING_TIMER_INFO_INITIALIZED

Fired after the initialization of swing information for the unit. The UnitSwingTimerInfo method is only usable after this event.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |

### UNIT_SWING_TIMER_START

Fired when a weapon or ranged swing starts.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand that start to swing ("mainhand", "offhand" or "ranged") |

### UNIT_SWING_TIMER_UPDATE

Fired when weapon speed changes.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand speed that update ("mainhand" or "offhand") |

### UNIT_SWING_TIMER_CLIPPED

Fired if a weapon swing is clipped by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| hand | string - The hand that is clipped "mainhand" or "offhand" |

### UNIT_SWING_TIMER_PAUSED

Fired if a weapon swing is paused by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| hand | string - The hand that is paused "mainhand" or "offhand" |

### UNIT_SWING_TIMER_STOP

Fired when a weapon or ranged swing ends.

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| hand | string - the hand that end a swing ("mainhand", "offhand" or "ranged") |

### UNIT_SWING_TIMER_DELTA

Fired when delta calculation between MH and OH update

| Property | Description |  
| ----------- | ----------- |
| unitId | string - type of the unit ("player" or "target") |
| swingDelta | number - Delta in seconds between MH and OH. |


## API METHODS

### UnitSwingTimerInfo(unitId, hand)

Returns the `hand`'s current swing state for the given unit type. Can only be used after the UNIT_SWING_TIMER_INFO_INITIALIZED event.

```
speed, expirationTime, lastSwing = UnitSwingTimerInfo(unitId, hand)
```

- Arguments
    - unitId
        - string - type of the unit ("player" or "target")
    - hand
        - string - The hand to get information for ("mainhand", "offhand" or "ranged")
- Returns
    - speed
        - number - weapon speed
    - expirationTime
        - number - end of swing relative to GetTime()
    - lastSwing
        - number - last swing relative to GetTime()

## API EVENTS Backward compatibility

Maintain backward compatibility. The following events are still fired only for the player.

### SWING_TIMER_INFO_INITIALIZED

Fired after the initialization of the swing information for the player. The SwingTimerInfo method is only usable after this event.

### SWING_TIMER_START

Fired when a weapon or ranged swing starts.

| Property | Description |  
| ----------- | ----------- |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand that start to swing ("mainhand", "offhand" or "ranged") |

### SWING_TIMER_UPDATE

Fired when weapon speed changes.

| Property | Description |  
| ----------- | ----------- |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand speed that update ("mainhand" or "offhand") |

### SWING_TIMER_CLIPPED

Fired if a weapon swing is clipped by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| hand | string - The hand that is clipped "mainhand" or "offhand" |

### SWING_TIMER_PAUSED

Fired if a weapon swing is paused by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| hand | string - The hand that is paused "mainhand" or "offhand" |

### SWING_TIMER_STOP

Fired when a weapon or ranged swing ends.

| Property | Description |  
| ----------- | ----------- |
| hand | string - the hand that end a swing ("mainhand", "offhand" or "ranged") |

### SWING_TIMER_DELTA

Fired when delta calculation between MH and OH update

| Property | Description |  
| ----------- | ----------- |
| swingDelta | number - Delta in seconds between MH and OH. |

## API METHODS Backward compatibility

### API method SwingTimerInfo(hand)

Returns the `hand`'s current swing state for the player. Can only be used after the SWING_TIMER_INFO_INITIALIZED event.

```
speed, expirationTime, lastSwing = SwingTimerInfo(hand)
```

- Arguments
    - hand
        - string - The hand to get information for ("mainhand", "offhand" or "ranged")
- Returns
    - speed
        - number - weapon speed
    - expirationTime
        - number - end of swing relative to GetTime()
    - lastSwing
        - number - last swing relative to GetTime()
