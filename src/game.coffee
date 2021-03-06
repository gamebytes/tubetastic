d = (msg) ->
  document.getElementById('debug')?.innerHTML = msg
  console.log msg

window.addEventListener 'load', ( -> FastClick.attach(document.body) ), false

# via: http://indiegamr.com/quickfix-to-enable-touch-of-easeljs-displayobjects-in-cocoonjs/
createjs.Stage.prototype._updatePointerPosition = (id, pageX, pageY) ->
  rect = this._getElementRect this.canvas
  w = this.canvas.width
  h = this.canvas.height
  rect.left = 0 if isNaN(rect.left)
  rect.top = 0 if isNaN(rect.top)
  rect.right = w if isNaN(rect.right)
  rect.bottom = h if isNaN(rect.bottom)
  pageX -= rect.left
  pageY -= rect.top
  pageX /= (rect.right-rect.left)/w
  pageY /= (rect.bottom-rect.top)/h
  o = this._getPointerData(id);
  if (o.inBounds = (pageX >= 0 && pageY >= 0 && pageX <= w-1 && pageY <= h-1))
    o.x = pageX
    o.y = pageY
  else if this.mouseMoveOutside
    o.x = if pageX < 0 then 0 else (pageX > w-1 ? w-1 : pageX)
    o.y = if pageY < 0 then 0 else (pageY > h-1 ? h-1 : pageY)
  o.rawX = pageX;
  o.rawY = pageY;
  if id == this._primaryPointerID
    this.mouseX = o.x
    this.mouseY = o.y
    this.mouseInBounds = o.inBounds

# Port of seedrandom.js by David Bau: http://davidbau.com/encode/seedrandom.js
class SeedRandom
  @init: (initVector) ->
    SeedRandom.initialize window, [], Math, 256, 6, 52
    Math.seedrandom initVector
  @initialize: (global, pool, math, width, chunks, digits) ->
    startdenom = math.pow(width, chunks)
    significance = math.pow(2, digits)
    overflow = significance * 2
    mask = width - 1
    class ARC4
      constructor: (key) ->
        t = key.length
        keylen = key.length
        i = 0
        j = @i = @j = 0
        s = @S = []
        key = [keylen++] unless keylen
        s[i] = i++ while i < width
        for i in [0..width-1]
          s[i] = s[j = mask & (j + key[i % keylen] + (t = s[i]))]
          s[j] = t
        @g width
      g: (count) =>
        r = 0
        t = 0
        i = @i
        j = @j
        s = @S
        while count--
          t = s[i = mask & (i + 1)]
          r = r * width + s[mask & ((s[i] = s[j = mask & (j + t)]) + (s[j] = t))]
        @i = i
        @j = j
        r
    flatten = (obj, depth) ->
      result = []
      typ = (typeof obj)[0]
      if (depth != 0) and (typ == 'o')
        for prop of obj
          try
            result.push(flatten(obj[prop], depth - 1))
          catch e
      return result if result.length
      return obj if typ == 's'
      return obj + '\0'
    mixkey = (seed, key) ->
      stringseed = seed + ''
      smear = 0
      j = 0
      while j < stringseed.length
        key[mask & j] = mask & ((smear ^= key[mask & j] * 19) + stringseed.charCodeAt(j++))
      tostring key
    autoseed = (seed) ->
      try
        global.crypto.getRandomValues(seed = new Uint8Array(width))
        return tostring(seed)
      catch e
      return [+new Date, global, global.navigator.plugins, global.screen, tostring(pool)]
    tostring = (a) ->
      String.fromCharCode.apply(0, a)
    math['seedrandom'] = (seed, use_entropy) ->
      key = []
      if use_entropy
        to_flatten = [seed, tostring(pool)]
      else if 0 of arguments
        to_flatten = seed
      else
        to_flatten = autoseed()
      shortseed = mixkey(flatten(to_flatten, 3), key)
      arc4 = new ARC4(key)
      mixkey(tostring(arc4.S), pool)
      math['random'] = ->
        n = arc4.g chunks
        dd = startdenom
        x = 0
        while n < significance
          n = (n + x) * width
          dd *= width
          x = arc4.g 1
        while n >= overflow
          n /= 2
          dd /= 2
          x >>>= 1
        (n + x) / dd
      shortseed
    mixkey(math.random(), pool)

class ScoreKeeper
  @setScore: (score) =>
    # console.log "setScore:#{score}"
    if (window.localStorage) and (score > @getHighScore())
      window.localStorage.setItem('score:high', score)
  @getHighScore: =>
    return 0 unless window.localStorage
    highScore = window.localStorage.getItem('score:high') || 0
    # console.log "highScore:#{highScore}"
    return 0 if isNaN highScore
    return parseInt highScore

class AsyncSoundManager
  sounds = {}
  @play: (id, volume = 1.0) =>
    if sounds[id]
      createjs.Sound.play(id).setVolume(volume)
    @

class TileGraphics
  @cache = {}
  @resize: =>
    @cache = {}
  @get: (id) => @cache[id]
  @put: (id, val) => @cache[id] = val

class Tile extends createjs.Container
  @outletRotationsReverse =
    0: { N: 'N', E: 'E', S: 'S', W: 'W' }
    90: { N: 'W', E: 'N', S: 'E', W: 'S' }
    180: { N: 'S', E: 'W', S: 'N', W: 'E' }
    270: { N: 'E', E: 'S', S: 'W', W: 'N' }
  @outletDirections = [ 'N', 'E', 'S', 'W' ]
  @outletOffsets =
    N: { col:  0, row: -1 }
    E: { col:  1, row:  0 }
    S: { col:  0, row:  1 }
    W: { col: -1, row:  0 }
  @directionReverse =
    N: 'S'
    E: 'W'
    S: 'N'
    W: 'E'
  @POWER_NONE    = 0
  @POWER_SOURCED = 1
  @POWER_SUNK    = 2
  @arcShadow = {}
  @arcShadow[@POWER_NONE]    = null
  @arcShadow[@POWER_SOURCED] = new createjs.Shadow('#ff9900', 0, 0, 8)
  @arcShadow[@POWER_SUNK]    = new createjs.Shadow('#0099ff', 0, 0, 8)
  @tileBack = {}
  @tileBack[@POWER_NONE]    = 'rgba(255,255,255,0.25)'
  @tileBack[@POWER_SOURCED] = 'rgba(255,255,255,0.25)'
  @tileBack[@POWER_SUNK]    = 'rgba(255,255,255,0.25)'
  @arcColor = '#eee'
  @padding = 1 / 16
  constructor: (colNum, rowNum, x, y, s, board) ->
    # d 'new Tile(' + x + ',' + y + ',' + s + ')'
    @initialize colNum, rowNum, x, y, s, board
  initialize: (@colNum, @rowNum, x, y, s, @board) ->
    # d 'Tile::initialize'
    super()
    @power = Tile.POWER_NONE
    @id = Tile.makeId(@colNum, @rowNum)
    @outlets =
      N: false
      E: false
      S: false
      W: false
    @rotation = 0
    @outletRotation = 0
    @resize x, y, s
  hasOutletTo: (outletDirection) =>
    originalDirection = Tile.outletRotationsReverse[@outletRotation][outletDirection]
    hasOutlet = @outlets[originalDirection]
    hasOutlet
  getConnectedNeighbors: =>
    ret = {}
    for direction in Tile.outletDirections when @hasOutletTo direction
      neighbor = @neighbor direction
      continue unless neighbor and neighbor.hasOutletTo Tile.directionReverse[direction]
      ret[direction] = neighbor if neighbor
    # console.log "Tile(#{@id}) has neighbors:", ret
    ret
  neighbor: (outletDirection) =>
    offsets = Tile.outletOffsets[outletDirection]
    return @board.tileAt @colNum + offsets.col, @rowNum + offsets.row
  setPower: (@power) =>
  isSourced: => @power == Tile.POWER_SOURCED
  isSunk: => @power == Tile.POWER_SUNK
  @makeId: (colNum, rowNum) => [colNum, rowNum].join(',')
  resize: (x, y, s) =>
    @midpoint = s / 2
    @x = x + @midpoint
    @y = y + @midpoint
    @regX = @midpoint
    @regY = @midpoint

class SourceTile extends Tile
  initialize: (colNum, rowNum, x, y, s, board) ->
    # d 'SourceTile::initialize(' + x + ',' + y + ',' + s + ')'
    super colNum, rowNum, x, y, s, board
    @back = null
    @arc = null
    @power = Tile.POWER_SOURCED
    @outlets['E'] = true
    @resize x, y, s
  setPower: =>
  resize: (x, y, s) =>
    super x, y, s
    @removeAllChildren()
    gfxBack = TileGraphics.get 'sourceBack'
    unless gfxBack
      gfxBack = new createjs.Graphics().beginFill(Tile.tileBack[@power]).drawRoundRect(s * Tile.padding * 3, s * Tile.padding * 3, s * (1 - (6 * Tile.padding)), s * (1 - (6 * Tile.padding)), s * Tile.padding * 6)
      TileGraphics.put 'sourceBack', gfxBack
    back = new createjs.Shape(gfxBack)
    back.shadow = Tile.arcShadow[@power]
    @addChild back
    gfxArc = TileGraphics.get 'sourceArc'
    unless gfxArc
      gfxArc = new createjs.Graphics().beginFill(Tile.arcColor).drawCircle(@midpoint, @midpoint, s / 16).drawRect(@midpoint, @midpoint - s / 16, @midpoint, s / 8)
      TileGraphics.put 'sourceArc', gfxArc
    arc = new createjs.Shape(gfxArc)
    arc.shadow = Tile.arcShadow[@power]
    @addChild arc
    @


class SinkTile extends Tile
  initialize: (colNum, rowNum, x, y, s, board) ->
    # d 'SinkTile::initialize(' + x + ',' + y + ',' + s + ')'
    super colNum, rowNum, x, y, s, board
    @outlets['W'] = true
    @power = Tile.POWER_SUNK
    @resize x, y, s
  setPower: (power) =>
    return if power == @power
    AsyncSoundManager.play 'boom' if (power == Tile.POWER_SOURCED) and @board.settled
    @arc.shadow = Tile.arcShadow[power]
    # console.log "Sink(#{@colNum},#{@rowNum}).setPower(#{@power} => #{power})"
    @power = power
    @
  resize: (x, y, s) =>
    super x, y, s
    @removeAllChildren()
    gfxBack = TileGraphics.get 'sinkBack'
    unless gfxBack
      gfxBack = new createjs.Graphics().beginFill(Tile.tileBack[@power]).drawRoundRect(s * Tile.padding * 3, s * Tile.padding * 3, s * (1 - (6 * Tile.padding)), s * (1 - (6 * Tile.padding)), s * Tile.padding * 6)
      TileGraphics.put 'sinkBack', gfxBack
    back = new createjs.Shape(gfxBack)
    back.shadow = Tile.arcShadow[@power]
    @addChild back
    gfxArc = TileGraphics.get 'sinkArc'
    unless gfxArc
      gfxArc = new createjs.Graphics().beginFill(Tile.arcColor).drawCircle(@midpoint, @midpoint, s / 16).drawRect(0, @midpoint - s / 16, @midpoint, s / 8)
      TileGraphics.put 'sinkArc', gfxArc
    @arc = new createjs.Shape(gfxArc)
    @arc.shadow = Tile.arcShadow[@power]
    @addChild @arc
    @

class TubeTile extends Tile
  outletRadians =
    N: Math.PI / 2
    E: 0
    S: 3 * Math.PI / 2
    W: Math.PI
  outletProbabilities = [
    { p: 0.05, c: 4, n: 1, b: [ 15 ] }
    { p: 0.50, c: 3, n: 4, b: [ 7, 11, 13, 14 ] }
    { p: 0.90, c: 2, n: 6, b: [ 3, 5, 6, 9, 10, 12 ] }
    { p:    0, c: 1, n: 4, b: [ 8, 4, 2, 1 ] }
  ]
  outletPaths = [
    { s: 'N', d: 'S', t: 'L', x1:  0, y1: -1, x2: 0, y2: 1 }
    { s: 'E', d: 'W', t: 'L', x1: -1, y1:  0, x2: 1, y2: 0 }
    { s: 'N', d: 'E', t: 'A', x:  1, y: -1, a1: outletRadians.N, a2: outletRadians.W, x1:  0, y1: -1, x2:  1, y2:  0 }
    { s: 'E', d: 'S', t: 'A', x:  1, y:  1, a1: outletRadians.W, a2: outletRadians.S, x1:  1, y1:  0, x2:  0, y2:  1 }
    { s: 'S', d: 'W', t: 'A', x: -1, y:  1, a1: outletRadians.S, a2: outletRadians.E, x1:  0, y1:  1, x2: -1, y2:  0 }
    { s: 'W', d: 'N', t: 'A', x: -1, y: -1, a1: outletRadians.E, a2: outletRadians.N, x1: -1, y1:  0, x2:  0, y2: -1 }
    { b: 8, t: 'L', x1:    0, y1:  -1, x2:    0, y2: -1/4 }
    { b: 4, t: 'L', x1:  1/4, y1:   0, x2:    1, y2:    0 }
    { b: 2, t: 'L', x1:    0, y1: 1/4, x2:    0, y2:    1 }
    { b: 1, t: 'L', x1:   -1, y1:   0, x2: -1/4, y2:    0 }
  ]
  outletRotations =
    0: { N: 'N', E: 'E', S: 'S', W: 'W' }
    90: { N: 'E', E: 'S', S: 'W', W: 'N' }
    180: { N: 'S', E: 'W', S: 'N', W: 'E' }
    270: { N: 'W', E: 'N', S: 'E', W: 'S' }
  initialize: (colNum, rowNum, x, y, s, board) ->
    # d 'TubeTile::initialize(' + x + ',' + y + ',' + s + ')'
    super colNum, rowNum, x, y, s, board
    r = Math.random()
    @outletBits = 0
    @outletCount = 0
    for prob in outletProbabilities
      if (prob.p == 0) or (r <= prob.p)
        @outletBits = prob.b[Math.floor(Math.random() * prob.b.length)]
        @outletCount = prob.c
        break
    @setBits @outletBits
    @spinRemain = 0
    @tileSize = s
    @resize x, y, s
    @ready = true
    # @addEventListener 'click', @onClick
    # AsyncSoundManager.load 'sh'
  setBits: (@outletBits) =>
    @outlets =
      N: !!(@outletBits & 8)
      E: !!(@outletBits & 4)
      S: !!(@outletBits & 2)
      W: !!(@outletBits & 1)
    @drawArc() if @arc
  drawArc: =>
    @removeChild @arc if @arc
    gfxArc = TileGraphics.get 'tileArc' + @outletBits
    unless gfxArc
      gfxArc = new createjs.Graphics().setStrokeStyle(@tileSize / 8).beginStroke(Tile.arcColor)
      for path in outletPaths when (('b' of path) and (@outletBits == path.b)) or (('s' of path) and @outlets[path.s] and @outlets[path.d])
        gfxArc.moveTo(path.x2 * @midpoint, path.y2 * @midpoint)
        switch path.t
          when 'L' then gfxArc.lineTo(path.x1 * @midpoint, path.y1 * @midpoint)
          when 'A' then gfxArc.arc(path.x * @midpoint, path.y * @midpoint, @midpoint, path.a1, path.a2, false)
          else false
      gfxArc.endStroke()
      TileGraphics.put 'tileArc' + @outletBits, gfxArc
    @arc = new createjs.Shape(gfxArc)
    @arc.shadow = Tile.arcShadow[@power]
    @arc.x = @midpoint
    @arc.y = @midpoint
    @addChild @arc
  resize: (x, y, s) =>
    super x, y, s
    @tileSize = s
    @removeAllChildren()
    gfxBack = TileGraphics.get 'tileBack'
    unless gfxBack
      gfxBack = new createjs.Graphics().beginFill(Tile.tileBack[Tile.POWER_NONE]).drawRoundRect(@tileSize * Tile.padding, s * Tile.padding, s * (1 - (2 * Tile.padding)), s * (1 - (2 * Tile.padding)), s * Tile.padding * 2)
      TileGraphics.put 'tileBack', gfxBack
    @back = new createjs.Shape(gfxBack)
    @back.shadow = Tile.arcShadow[@power]
    @addChild @back
    @drawArc()
    @
  onClick: (evt) =>
    # console.log "TubeTile(#{@id})::click", evt, @board.ready
    return unless @board.ready
    @spinRemain++
    @spin() if @ready
  spin: =>
    if (@spinRemain > 0)
      AsyncSoundManager.play 'sh', 0.3
      @ready = false
      @spinRemain--
      createjs.Tween.get(@)
        .to({scaleX:0.7,scaleY:0.7}, 25)
        .to({rotation:@rotation + 90}, 100)
        .to({scaleX:1,scaleY:1}, 25)
        .call(@spin)
      @setPower false
      @board.interruptSweep()
    else
      @rotation %= 360 if @rotation >= 360
      @outletRotation = @rotation
      @board.readyForSweep()
      @ready = true
  setPower: (power) =>
    return if power == @power
    shadow = Tile.arcShadow[power]
    @arc.shadow = shadow
    @back.shadow = shadow
    @power = power
    @
  vanish: (onGone) =>
    @ready = false
    @setPower Tile.POWER_NONE
    if @board.settled
      createjs.Tween.get(@)
        .to({alpha:0, scaleX: 0, scaleY: 0}, 500)
        .call(onGone)
    else
      onGone()
      # console.log "skipping anim for Tile(#{@id}).vanish"
    @
  dropTo: (colNum, rowNum, x, y, onDropped) =>
    # console.log "Tile(#{@id}).dropTo(#{colNum},#{rowNum},#{x},#{y})"
    @ready = false
    @setPower Tile.POWER_NONE
    dropDone = =>
      @colNum = colNum
      @rowNum = rowNum
      @id = Tile.makeId(colNum, rowNum)
      onDropped(this, colNum, rowNum)
      @ready = true
    if @board.settled
      createjs.Tween.get(@)
        .to({x: x + @midpoint, y: y + @midpoint}, 250)
        .call(dropDone)
    else
      @x = x + @midpoint
      @y = y + @midpoint
      dropDone()
      # console.log "skipping anim for Tile(#{@id}).drop"
    @

class ProgressBar extends createjs.Container
  constructor: (@progress, @w, @h) ->
    @initialize @progress, @w, @h
  initialize: (@progress, @w, @h) =>
    super()
    @resize @w, @h
    @
  resize: (@w, @h) =>
    # console.log 'bar:', @progress, @w, @h
    padding = @h / 8
    @removeAllChildren()
    gfxBorder = new createjs.Graphics().beginFill(Tile.arcColor).drawRect(0, 0, @w, @h)
    border = new createjs.Shape(gfxBorder)
    border.shadow = Tile.arcShadow[Tile.POWER_NONE]
    @addChild border
    gfxBar = new createjs.Graphics().beginFill('#777').drawRect(padding, padding, (@w - (padding * 2)) * @progress, @h - (padding * 2))
    bar = new createjs.Shape(gfxBar)
    @addChild bar
    @
  setProgress: (@progress) => @resize @w, @h

class Splash extends createjs.Container
  constructor: (@stage, @onComplete) ->
    @manifest = []
    @progress = null
    @lastProgress = 0
    @addSoundToManifest 'sh'
    @addSoundToManifest 'boom'
    @initialize()
    @resize()
  addSoundToManifest: (id) =>
    @manifest.push {id: id, src: "audio/tube-#{id}.ogg|audio/tube-#{id}.mp3|audio/tube-#{id}.wav"}
  initialize: =>
    super()
    queue = new createjs.LoadQueue()
    queue.installPlugin createjs.Sound
    # queue.addEventListener 'complete', =>
      # @progress?.alpha = 0.25
    queue.addEventListener 'progress', (evt) =>
      # console.log "loader progress: #{evt.progress}"
      @lastProgress = evt.progress
      @progress?.setProgress @lastProgress
      @resize()
      return
    queue.loadManifest @manifest
  resize: =>
    w = @stage.canvas.width
    h = @stage.canvas.height
    @removeAllChildren()
    title1 = new createjs.Text('Tube', Math.min(Math.max(w / 8, h / 8), w / 6) + 'px Satisfy', Tile.arcColor)
    title1.textAlign = 'right'
    title1.shadow = Tile.arcShadow[Tile.POWER_SOURCED]
    title1.regX = 0
    title1.regY = title1.getMeasuredHeight() / 2
    title1.y = h / 6
    title2 = new createjs.Text('Tastic!', Math.min(Math.max(w / 8, h / 8), w / 6) + 'px Satisfy', Tile.arcColor)
    title2.textAlign = 'left'
    title2.shadow = Tile.arcShadow[Tile.POWER_SUNK]
    title2.regX = 0
    title2.regY = title2.getMeasuredHeight() / 2
    title2.y = title1.y
    totalWidth = title1.getMeasuredWidth() + title2.getMeasuredWidth()
    title2.x = title1.x = (w - totalWidth) / 2 + title1.getMeasuredWidth()
    @addChild title1
    @addChild title2
    credit = new createjs.Text('by Rick Osborne', Math.max(w / 64, h / 64) + 'px Kite One', Tile.arcColor)
    credit.alpha = 0.25
    credit.shadow = Tile.arcShadow[Tile.POWER_NONE]
    credit.textAlign = 'center'
    credit.x = (w / 2) + (totalWidth / 4)
    credit.y = title2.y + (title2.getMeasuredLineHeight() * 0.6)
    credit.regY = 0
    @addChild credit
    highScore = ScoreKeeper.getHighScore()
    if highScore > 0
      score = new createjs.Text("High Score: #{highScore}", Math.min(Math.max(w / 32, h / 32), w / 16) + 'px Kite One', Tile.arcColor)
      score.alpha = 0.4
      score.shadow = Tile.arcShadow[Tile.POWER_NONE]
      score.textAlign = 'center'
      score.x = w / 2
      score.regY = score.getMeasuredHeight() / 2
      score.y = h * 2 / 5
      @addChild score
    y = h * 3 / 5
    tw = w / 13
    if @lastProgress < 1
      progress = new ProgressBar(@lastProgress, w / 2, title1.getMeasuredLineHeight() / 3)
      progress.x = w / 4
      progress.y = y
      @addChild progress
    else
      start = new StartButton(tw * 3, tw, => @onComplete())
      start.x = w / 2
      start.regX = tw * 3 / 2
      start.y = y
      start.regY = tw / 2
      @addChild start
      inst = new createjs.Text('Tap the square to complete the connection and start a new game.', Math.min(Math.max(w / 36, h / 36), w / 20) + "px Kite One", Tile.arcColor)
      inst.lineWidth = w / 2
      inst.textAlign = 'center'
      inst.regX = 0
      inst.regY = 0
      inst.x = w / 2
      inst.y = h * 3 / 4
      @addChild inst

class StartButton extends createjs.Container
  constructor: (@w, @h, @onStart) ->
    @initialize @w, @h
  initialize: (@w, @h) ->
    super()
    @resize @w, @h
    @ready = true
    @settled = true
    @
  resize: (@w, @h) =>
    @removeAllChildren()
    source = new SourceTile(0, 1, 0, 0, @h, @)
    @addChild source
    @tile = new TubeTile(1, 0, @w / 3, 0, @h, @)
    @tile.setBits 10
    @addChild @tile
    sink = new SinkTile(2, 0, @w * 2 / 3, 0, @h, @)
    @addChild sink
    @
  interruptSweep: ->
  readyForSweep: =>
    return unless @tile.rotation == 90 or @tile.rotation == 270
    @tile.vanish => @onStart()

class GameMenu extends createjs.Container
  @digitCount = 9
  constructor: (@w, @h) ->
    @initialize @w, @h
  initialize: (@w, @h) ->
    super()
    @score = 0
    @resize @w, @h
    @
  resize: (@w, @h) =>
    @removeAllChildren()
    back = new createjs.Shape()
    back.graphics.beginFill('#000').drawRoundRect(0, 0, @w, @h, @h / 2)
    @addChild back
    @digits = []
    y = @h * TubetasticGame.fontFudge
    tw = @w / (GameMenu.digitCount + 1)
    for digitNum in [0..GameMenu.digitCount-1]
      digit = new createjs.Text('0', @h + 'px Kite One', Tile.arcColor)
      digit.textAlign = 'center'
      digit.regX = 0
      # digit.regY = digit.getMeasuredLineHeight() / 2
      digit.x = tw * (digitNum + 1)
      digit.y = y
      digit.lineHeight = @h
      @digits.push digit
      @addChild digit
    @setScore @score
    @
  setScore: (@score) =>
    n = @score
    for digitNum in [GameMenu.digitCount-1..0] by -1
      @digits[digitNum].text = n % 10
      n = Math.floor(n / 10)

class GameBoard extends createjs.Container
  constructor: (@stage, @sourceCount, @hopDepth) ->
    # d 'new GameBoard(...,rows=' + @sourceCount + ',cols=' + @hopDepth + ')'
    @initialize @sourceCount, @hopDepth
  initialize: (@sourceCount, @hopDepth) ->
    # d 'GameBoard::initialize(rows=' + @sourceCount + ',cols=' + @hopDepth + ')'
    super()
    @board = []
    @menu = null
    @resize()
    for rowNum in [0..@sourceCount-1]
      row = []
      for colNum in [0..@hopDepth-1]
        tileType = TubeTile
        if colNum == 0
          tileType = SourceTile
        else if colNum == @hopDepth - 1
          tileType = SinkTile
        tile = new tileType(colNum, rowNum, @xForColumn(colNum), @yForRow(rowNum), @tileSize, @)
        @addChild tile
        row.push tile
      @board.push row
    @settled = false
    @score = 0
    @menu = new GameMenu(@tileSize * @hopDepth, @tileSize * 0.8)
    @menu.alpha = 0.25
    @menu.x = 0
    @menu.y = @yForRow(@sourceCount) + (@tileSize * 0.2) # one extra
    @addChild @menu
    @powerSweep()
    return
  resize: =>
    @tileSize = Math.floor Math.min(@stage.canvas.width / @hopDepth, @stage.canvas.height / (@sourceCount + 1))
    @x = Math.floor (@stage.canvas.width - (@tileSize * @hopDepth)) / 2
    @y = Math.floor (@stage.canvas.height - (@tileSize * (@sourceCount + 1))) / 2
    # console.log "board #{@x},#{@y} size:#{@tileSize} #{@stage.canvas.width}x#{@stage.canvas.height}"
    TileGraphics.resize()
    if @menu
      @menu.y = @yForRow(@sourceCount) + (@tileSize * 0.2) # one extra
      @menu.resize @tileSize * @hopDepth, @tileSize * 0.8
    for row, rowNum in @board
      for tile, colNum in row
        tile.resize @xForColumn(colNum), @yForRow(rowNum), @tileSize
  xForColumn: (colNum) => colNum * @tileSize
  yForRow: (rowNum) => rowNum * @tileSize
  readyForSweep: =>
    @sweepTimer = setTimeout(@powerSweep, 125) unless @sweepTimer
  interruptSweep: =>
    if @sweepTimer
      clearTimeout @sweepTimer
      @sweepTimer = null
  powerSweep: =>
    sweepStart = Date.now()
    @ready = false
    toCheck = []
    toCheck.push @board[rowNum][0] for rowNum in [@sourceCount - 1..0] by -1
    sourced = {}
    sunk = {}
    neither = {}
    toRemove = {}
    points = 0
    for rowNum in [0..@sourceCount-1]
      for colNum in [0..@hopDepth-1]
        neither[Tile.makeId(colNum, rowNum)] = @board[rowNum][colNum]
    while toCheck.length > 0
      tile = toCheck.pop()
      tile.setPower Tile.POWER_SOURCED unless tile.power == Tile.POWER_SOURCED
      sourced[tile.id] = true
      delete neither[tile.id]
      toRemove[tile.id] = tile if tile instanceof SinkTile
      toCheck.push neighbor for direction, neighbor of tile.getConnectedNeighbors() when neighbor.id not of sourced
    toCheck.push @board[rowNum][@hopDepth-1] for rowNum in [@sourceCount - 1..0] by -1 when "#{@hopDepth-1},#{rowNum}" not of sourced
    while toCheck.length > 0
      tile = toCheck.pop()
      tile.setPower Tile.POWER_SUNK unless tile.power == Tile.POWER_SUNK
      sunk[tile.id] = true
      delete neither[tile.id]
      toCheck.push neighbor for direction, neighbor of tile.getConnectedNeighbors() when (neighbor.id not of sourced) and (neighbor.id not of sunk)
    tile.setPower Tile.POWER_NONE for id, tile of neither when tile.power isnt Tile.POWER_NONE
    toCheck.push tile for id, tile of toRemove
    if toCheck.length == 0
      @ready = true
      @sweepTimer = null
      @settled = true
      # d 'powerSweep took ' + (Date.now() - sweepStart) + 'ms'
      # console.log 'board ready'
    vanishCount = 0
    dropCount = 0
    toVanish = []
    toDrop = []
    onVanished = =>
      vanishCount--
      return unless vanishCount <= 0
      # console.log 'all destroyed'
      onDropped = (tile, colNum, rowNum) =>
        dropCount--
        @board[rowNum][colNum] = tile
        return unless dropCount <= 0
        setTimeout @powerSweep, 0
      for colNum in [1..@hopDepth-2]
        destRowNum = @sourceCount
        colX = @xForColumn(colNum)
        for rowNum in [@sourceCount-1..0] by -1
          tile = @board[rowNum][colNum]
          if tile.id of toRemove
            @board[rowNum][colNum] = null
            @removeChild tile
          else
            destRowNum--
            if destRowNum > rowNum
              dropCount++
              toDrop.push {tile: tile, colNum: colNum, rowNum: destRowNum, colX: colX}
              @board[rowNum][colNum] = null
        for rowNum in [destRowNum-1..0] by -1
          dropCount++
          tile = new TubeTile(-2, -2, colX, @yForRow(rowNum - destRowNum), @tileSize, @)
          toDrop.push {tile: tile, colNum: colNum, rowNum: rowNum, colX: colX}
          @addChild tile
      drop.tile.dropTo drop.colNum, drop.rowNum, drop.colX, @yForRow(drop.rowNum), onDropped for drop in toDrop
    while toCheck.length > 0
      tile = toCheck.pop()
      toRemove[tile.id] = tile
      toCheck.push neighbor for direction, neighbor of tile.getConnectedNeighbors() when neighbor.id not of toRemove
      continue unless tile instanceof TubeTile
      toVanish.push tile
      vanishCount++
    for tile in toVanish
      tile.vanish onVanished
      points++
    if @settled
      @score += points
      @menu.setScore @score
      ScoreKeeper.setScore @score
    @
  tileAt: (colNum, rowNum) =>
    return @board[rowNum][colNum] if (colNum >= 0) and (colNum < @hopDepth) and (rowNum >= 0) and (rowNum < @sourceCount)
    return null

class TubetasticGame
  @fontFudge = switch
    when navigator.userAgent.indexOf('Safari') > -1 then -0.166667
    when navigator.userAgent.indexOf('Firefox') > -1 then 0.166667
    else 0
  constructor: (canvasName) ->
    SeedRandom.init(Math.random())
    # d 'TubetasticGame'
    # AsyncSoundManager.load 'sh'
    # AsyncSoundManager.load 'boom'
    @stage = new createjs.Stage(canvasName)
    createjs.Ticker.setFPS 30
    createjs.Ticker.useRAF = true
    createjs.Ticker.addEventListener 'tick', => @stage.update()
    @splash = new Splash(@stage, @loaded)
    @stage.addChild @splash
    @board = null
    createjs.Touch.enable @stage, true, false
    window.onresize = =>
      context = @stage.canvas.getContext '2d'
      devicePixelRatio = window.devicePixelRatio || 1
      backingStoreRatio = context.webkitBackingStorePixelRatio || context.mozBackingStorePixelRatio || context.msBackingStorePixelRatio || context.oBackingStorePixelRatio || context.backingStorePixelRatio || 1
      ratio = devicePixelRatio / backingStoreRatio
      ratio = 1 if devicePixelRatio == backingStoreRatio
      @stage.canvas.width = window.innerWidth * ratio
      @stage.canvas.height = window.innerHeight * ratio
      context.scale ratio, ratio
      @board?.resize()
      @splash?.resize()
    window.onresize()
  loaded: =>
    @stage.removeAllChildren()
    @splash = null
    @board = new GameBoard(@stage, 8, 7)
    @stage.addChild @board

new TubetasticGame('gameCanvas')
