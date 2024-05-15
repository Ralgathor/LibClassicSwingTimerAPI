# LibClassicSwingTimerAPI

There is no relevant WOW API to have an easily accessible state of the swing timer. This library fires custom EVENTS that can be used in other ADDONs to produce swing timer information.

## Usage example:

#### Use in Addon
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

#### Use in WeakAuras

The LibClassicSwingTimerAPI fire the events as WeakAuras custom events that can be use on Custom Triggers. The following auras export strings are examples on how to use the lib in WeakAuras.

###### Main hand aura

```
!WA:2!9zv3UTTnu4AyGUnHMIwxScKHTbnJTIwSK08t)ddiOWkXU2dj2UYknTBTqHsKYITYKeuuoX5IHTGHHEDUB3Sl8JGXEak6tGqWW21lpc5jyKuQo)6jaBrE4HN)pFhvOwPELGLGV9UdJza(B2edfHF6qSpL0HMW9rF(L470kiigjQ)yZlPF4dYj8UNUu3FwsyeG4hs5TPyIWBLQnDQAFGwA2ubqGPKcSRFQ9RtHiRkB406ipG)B6YPje4k0ik)7luOq7IZp393tWXD7I4X)XT45l)BlXagYZpjwq7DyCIhQpIi6KeeG3zK7kv6442XPITZqiYts0rYmVE11AxBJ1S1S6vhbIeHJVABosEv7oTRU2AhMj2vt4AdK9NbjeF1QBFhdt5doWeipZfr6px82ys3ockZ8Nw2KGJmfHiIMl1dhjs4KlG7zobngcbNXuWtq67HIIrtwazmpEpAhgoZkDW9YVpbAi)zLqWcpweyaIN5IXSh2zZgnFIRtJ1RANfFmpjLnAVAfNQNIu7kB0P6Q2eqpuSr6v3PW)mowOL5mM5w0PnKzmdbe44OLMvZLx2S85LDztjNzsrZrpaMOUC5thjVGa(YtkmyoR5tqc1Q8e2jIKNkmp20K5UYTA70OvZoz2JYcoJ5CSzMNPveoJIVOAGtN7KwT(95p(mIAzZli3oXiHuR)VE6zpma8bI5LlJYQ5DvTvP3ypPngf1agB8b6Hyik9Q7NqYBanUv6v(T0RNwkDQ0Ppmjg5cI2gmiwP1Ts)cJ0Pt)SutJ0BmCfkbIvEr8Ek2uLLBLw2yeeh)ADTuF0IaYawPmn5Kj)1ODX(S7oUAtKLj)GV9Jl8ktkx(EP83l(kLxWUoqlWCHOGwkQXVC91ikfLphjbMqCci6zsefPOFZ(acUNoo)a7ybGlQ9Eeig1rWrKUIWpkDklcLGoaMJhOJr8yKuSW49uSQGxsN3svRul9UYlKoF6cPlMUu68Ebycoo8SK3ZdWZa5Q)4)Db9Z5xuuIEfdek1IcFVg0mdS9ffgkXTSrDvr1V7MPtDGC7XON5ecOCugH3onRKaTJWnoeaPB)8mPuCFnn1FL)ggB6X7CL3ugqCz5lSfY6p4HzsaffOX2t)e2n0uajYSMmW4RhxyvrU9OmPG3bb1e)f2xFbcxjv3iuxG)a3GikLh(EndVwwhGdgKE5HC1icKJKOvZwnRYU2jCIXJikMofx6TQJoiB2tU)vyOM9JZ87NRFIGDTAC8UMpnbaLbxGPJd7RMKfY4iFSQqP4PcIVitjF(LYm6(sw8IqBDGE32uoCtoGT3M5loySQv1kwnL1t5EZjgxoSrZMsCX1QwZH9LtYCY2vGzojg6rHUQkMTowNDW7IMMDNjDd4aj(o23veYrXH0i4G8azUpwWleH7gkw2kIcG18eGijO5nT7LejWgwsSc)BM6Ay7hbIJvRSILkuT4qDrRLKDOQxCXkRUk7AsuGkqvsgbrW1b7e6j7KcWDn2)4IRlFw2KOWd56cE9SCfiOSfId0OdXpiDoJ07Byj71e3AFi1ndlzR0RY(9iQpiYu1B2jhaEdjxvecz)IMYTlNnLS8Dmohw9XxtIYmVXKbRhpWX8BpdIVXKaSpq25idYTyAxWyFnovSeN12UXtQ7CYg(NxyXemCu7(9Rx7EShYJQpsFA9S8cxLut4O9SIW7UlGdlJHSsRNp6YuRxtz4ktKozmZUDdfqyaWh9YvaYwosxla)LB0y2J3nBh9xQPVw4qb1VFgM5h3)D5gagcre7MvFwvBBqeleuCuax(1cs0tzJvr7Tv9))6vokRGQM6ivc0RZk2vR2m77mxzChkhtuAaTL1UuAVcJOCSSsthNhwVLDJFOvtNkRn0F8ifJryswXSCNm)lpjSum7A3BU5NBPzF0SD9E0cbEbluQ)F98)7p
```

###### Off hand aura

```
!WA:2!9zv3UTTXs4iiGKwI4ahvCcqkAZHrOnnb12X2nnNGcyeiklhRchjvk6yN2eqVK7sXnHAxILlLT8ffNJrrrUw3wGwa9ii0hGG8eqyCAVPxvFzVmpbD)Hr2Y2QeWwlNDMDM5BM5BzH1k1TeSe8v3DysmG9YTWqE4)6nQ1ndcsq8TlCiiLhsznJ5ykjXG1xVX6VE7x)lxq8mcq8f73IIjCVQ1A4uZ(q1byt5aPnfIV6eV)ykezvztNMwyFkj8aod3PdIL8Z3ILV83T49JrE(PjCA3Jss9q9qeE70Ga8EJCRwPTJBBNk2oJ0A4gIHOSRyR0YBDeiIho2QwmKWk72TQTXghP1F1uMkqI)1GuIVC1TVJHP4bhyce75Ii9wizxmPtBon287xXKGJm5HiIsl5ddXtzKZr75oHSyecoNjNLIu2HIsqt)a0kp(D0EXyDu6G7MBpbAi(tNwjX)N2BvVXJCDQ)4A2A4W8Ks2S1QvCQnHOwv2SDTvpq4QOO6WeJ3bFsWoRu2v2RWVngquozoZ8WAYOzoZqabogYuQAUYkMLpRZkBk0uFkknObbsBlpjAEoG(ktdkmN38riUCvEr7eO5eq94itu)k3SLt9MnARdhzemz0CCqMxSLcoLFpV2GjlFIGw97z3(uh1kMNt5DQaHWR)Jj6P3ma8oH5Dm2eqxuIHvkbZ9IJa9rSHqKNyCYru5zRxBJwRT5gdsj5JFg3k7Y)yMz2nZMj7ghLMGCbr7c6Ni96ozFSr2nY(3zFOrwPHvPeiwXlCGunPd2jRSXiio5fQoPEI5Y4s6(mh9PVbTd2p(Zg3PX1LX3LzF3sp3KYe)U8ZLXE8vbQJj3yj3rXHsEdxFAeL91ffpVvW8Gyeq0teSiIJ8LdaeCxf6EF7eoGXxlBglcLGEdcKGAZzishE4LoeMteOMayjiXXctoqQJeyYwWQlate2MTq2DVu2IzlLTC2cEbycoj80IpWdWQQcP1F4FUK65SlkkW9eax6wu4jPzFAHHcclBuhjw(vxlBMdfV6b8FzhgnLaZfeqziTGxD94BYr7XDv)tixKUUXUCrZKBmd5JL4qXbJvP8NghF9ZXa9cBPDWJuBLGIcuC5zVF8hOKi4)Ps00xD7GvfXRVvFk49qqLW)3H6lbEQoBk8g1(Vqu2Xb9ZU4qMK6h5ieA1OzJAXFY0I9iuhGFF3GikLfMndtK0sTIVZ0ma2x0CJ9D5Hmusinc2FOsRJ7ogKBfHhp7Am8(MFtkakkaathN4s6CoeaP7UTo4loHW8m6JUqS50cHUuORSGUZHQn3LYGBXaXhSv(cny0tus8Iq7epRgup(sZH1B0qqyUrT1CIVX0CI(TchoozKDOwne90hlQnEF01ZRe5jtHC3PtgD)zHcfk6fIWDc5RyfrbWNmqo8seSLSqpoisqAEn7UPrCSHTFeij5AzUgwcQnF9cHBKlos1)AjuhkhlxUYQRgpR4KQaLfEeebFmyVq9hwuDC5qn82MMY8rcq9u6JjHdzQHafZKKoumw92JhegNbTkU4cFjdOOqsUF28gwIPs(TgaPUA2MDeep)ue1hez6oNPGPVDof9Mc9QW5IJuj52L1mILVJXzyZhBLGqArJPZMp(cjZp)uxjymvg9S7zmqXJLi(4fB76pADh2E5FA1d)R)4)k)0kR9P0UfgPqW11fmMSCMYqhyfH3FFadMVlgcre7g1EsnBnVIJwV4Bxxsoga8rpRkqmps6ybypBZ6ZF8BZ3w95zkZchYP(908OVxVxxglyGBQVM0uLcMYcIUhBnM4EfzHYRDv7A1AydIIdbfT3vsj8dxEuGCFbBRywR4YPy4OETC2L8aYw3VBvgMi9cAhpbgeG7ymIYWIgpfSoC9M21)2MnCQSXq)XxXymct0JbI3mgCmr1flLep79wyXf(I5FW8D8EWsbEblvQ3)F7)o
```

###### Ranged hand aura
```
!WA:2!1zv3UTTrw4kiG0wI6ahv0G6fPzzeAYAJgReNMnixSEZkklhPSYsku0X2ztG8qodjNgQHedhAB5lwGySOixRhGEHEe0tqrEcgyuS3V(ripb78dTCSTmVWEMZC(BoNV57OcRxAqjyj4hEW40ea9DBHHSWV7JQ1D89trSTlCmiJfgt7KWWXKud6q9bfMaiEc5DJXeMBT6TDQBFSYq7ygqQBHKBCU9Bedrwv30PJf2lMeEeJIdcq00F7E08L)xl2WeKRxwklEWjPzUO9qewVmFF8bt6xRApN(9CQA7mrRr)qmeXVUTsl3giqelCQvDPiHv296wVvRt06VwgvLijv9ZiEYvlUKHP4JIyzuIjqCEFezVkPjie8(NThDqcwBQdEaYarGhjujkQjm1qhT0K72BRMTFEFNMBu3wNLMFUKn7UwvN6MNM5Y7jVe)6huyHP5IYr33mp4NpM33meqG6Sf7BQu18FVQz5oDDA2PDVYMIJv6yUQqkfqcqqTqL)K6sWrkbN3ZNEcleruUx(D(kH5QANC5JVGRw9c(EQb5fygntldfLEPd9bNkuuFL1yBcyak1WkJGzUjrGHi6yiYvGgCevpAJ6T6U(MTgLrYrpg3J)n)k3KFh(C8BFswkQpiAFWWuzu3L)dg8BZ)Z8V3GxACTyceRGZhjvtgGD5LnMaXP)IQBSNawLus3RC0EVvCa2l5VmTBXoh0H9Vw5TMXuX)F0BL5EYnak3KBSe6xCSe233lokM(IIIVpjE4GOeq0RepceU8DJae8avX7j2PmaLToFolsmb9reif1JrrKaw4xEmmhhRqr0uKWTW0JK6ilm8kwdayIWwEf(d(s(d5RWFeVIRpMGtdVO4JCb0AQuQXZ(FRO(U8III6EkGjdlk8Zzh2PWyX7nBuGSw(IBYN7yXwxG37cOXzeyUa)yksl4dlKChg6awF1FeYfx3(j9zcSs)ekYdlRdfhnvLY3njzHzyGEHT0o4jQJsrr(kQi(xN8TkjcARyz10trQzvvS9tAVGpabvcF)XAoSDYP0(O68Fr02X(d5xBmvYCHCecTA3PD9KF8QY9iuaWByF)O4yAiFoQ4sl1kzPRYa4qb4g71NfsrPHXrWHJvADg6yuUvewY8RtXhA(Ymau0aaMoojL035qamE)T1jFXZjm)gDRViX8QsHbXW(Yg6UhRoC)ykClki5OTYxC80eqIQSAlWHjZRRSNr8pUz72c2Tw1x3j52xvK07YRU7j6XUrNgvP77HpeTqENi)Yuips6lJgFwOqHIF4pX3O4mAdSz1gETYe(Z4Fn)FWRYTE)mYq25YqETc814xJxNV(mGDNUG)3fVHAW3Ax(luDk()K3IVtbE7B9fCBEpEx(lNrvNDHQo3zIU2z385nCMr4iNgUkZ4nd7IVz4BVWmqBSRcTX)BLVlZneHdczRAffdGVAKKkKiMSqdDzGiXaMBApilIHnS9IaPP3KhyyjMd4PxiAAYfNOydSeQdLKCpQ6ARLmVWtvHYNriicUb4Gq9VUO2uWTIkSxCg1djGOxqFmjCmvrPO45LdBeKuF6mALP4HUfFyL)kfOiKtFcFzdlbhh7EJGX91C37kOXdU0WSnfkzRMqUgyaiaTyz90LYljPWFOXvpE75iMC1Ilz(txygPHb)XgJum8PIFvITQRsp4uIf19xsKKrrjl2us87d8qVPgqW1qcSa03SzZLpB3Y9KgmrzwdDxIY0MFKve(Wdbuy(PyierSBx)v1TTomoEqbBL8WXSyV90tw(Q9(9YyyY86lTz6(IGykQP27lzb)pFZeFQyuRyaJGEP4N0Vexxks2aC7vZUE922GOKqqrxXn0hhyqXePZrHpkddNSZkvJc6Sud0l2EsmflWoQQ24gDSB(6oTDQ2AS30zUgtWen(uSZy0zm3xRuAY8pUYdR8Zl)0LdCF6k(U(RuAV)y7))p
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
