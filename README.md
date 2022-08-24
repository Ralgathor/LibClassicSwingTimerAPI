# LibClassicSwingTimerAPI

This lib give an overview of the Swing Timer state.

There is no relevant WOW API to have a real state of the Swing Timer so take in mind it can some time not be 100% accurate like all Swing Timer addons implementation!

## API EVENTS

### SWING_TIMER_START

Fired when a weapon or ranged swing start.

| Property | Description |  
| ----------- | ----------- |
| speed | number - weapon speed |
| expirationTime | number - end of swing relative to GetTime() |
| hand | string - the hand that start to swing ("mainhand", "offhand" or "ranged") |

### SWING_TIMER_END

Fired when a weapon or ranged swing end.

| Property | Description |  
| ----------- | ----------- |
| hand | string - the hand that start to swing ("mainhand", "offhand" or "ranged") |

### SWING_TIMER_UPDATE

Fired when weapon speed change

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

### SWING_TIMER_PAUSE

Fired if a weapon swing is paused by a spell cast.

| Property | Description |  
| ----------- | ----------- |
| hand | string - The hand that is paused "mainhand" or "offhand" |

### SWING_TIMER_DELTA

Fired when delta calculation between MH and OH update

| Property | Description |  
| ----------- | ----------- |
| swingDelta | number - Delta in seconds between MH and OH. |
