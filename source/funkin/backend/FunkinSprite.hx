package funkin.backend;

import flixel.animation.FlxAnimation;
import flixel.addons.effects.FlxSkewedSprite;
import flixel.graphics.frames.FlxFramesCollection;
import flixel.graphics.tile.FlxGraphicsShader;
import flixel.math.FlxAngle;
import flixel.math.FlxMatrix;
import flixel.math.FlxRect;
import flixel.math.FlxPoint;
import flixel.system.FlxAssets.FlxGraphicAsset;

import animate.internal.Timeline;
import animate.FlxAnimateFrames;
import animate.FlxAnimateController;

import funkin.backend.scripting.events.PlayAnimEvent.PlayAnimContext;
import funkin.backend.system.interfaces.IOffsetCompatible;
import funkin.backend.system.interfaces.IBeatReceiver;
import funkin.backend.utils.XMLUtil;

import haxe.io.Path;

enum abstract XMLAnimType(Int)
{
	var NONE = 0;
	var BEAT = 1;
	var LOOP = 2;

	public static function fromString(str:String, def:XMLAnimType = XMLAnimType.NONE)
	{
		return switch (StringTools.trim(str).toLowerCase())
		{
			case "none": NONE;
			case "beat" | "onbeat": BEAT;
			case "loop": LOOP;
			default: def;
		}
	}
}

class FunkinSprite extends FlxSkewedSprite implements IBeatReceiver implements IOffsetCompatible implements IXMLEvents
{
	public var extra:Map<String, Dynamic> = [];

	public var spriteAnimType:XMLAnimType = NONE;
	public var beatAnims:Array<BeatAnim> = [];
	public var name:String;
	public var zoomFactor:Float = 1;
	public var initialZoom:Float = 1;
	public var debugMode:Bool = false;
	public var animDatas:Map<String, AnimData> = [];

	/**
	 * ODD interval -> asynced; EVEN interval -> synced
	 */
	public var beatInterval(default, set):Int = 2;
	public var beatOffset:Int = 0;
	public var skipNegativeBeats:Bool = false;

	public var isAnimate(default, null):Bool = false;
	public var library(default, null):FlxAnimateFrames;
	public var timeline:Timeline;
	public var applyStageMatrix:Bool = false;
	public var atlasPath:String;
	public var animateAnim:FlxAnimateController;

	public function new(?X:Float = 0, ?Y:Float = 0, ?SimpleGraphic:FlxGraphicAsset)
	{
		super(X, Y);

		if (SimpleGraphic != null)
		{
			if (SimpleGraphic is String)
				loadSprite(cast SimpleGraphic);
			else
				loadGraphic(SimpleGraphic);
		}

		moves = false;
	}

	/**
	 * Gets the graphics and copies other properties from another sprite (Works both for `FlxSprite` and `FunkinSprite`!).
	 */
	public static function copyFrom(source:FlxSprite):FunkinSprite
	{
		var spr = new FunkinSprite();
		var casted:FunkinSprite = null;
		if (source is FunkinSprite)
			casted = cast source;

		@:privateAccess {
			spr.setPosition(source.x, source.y);
			spr.frames = source.frames;
			spr.animation.copyFrom(source.animation);
			spr.visible = source.visible;
			spr.alpha = source.alpha;
			spr.antialiasing = source.antialiasing;
			spr.scale.set(source.scale.x, source.scale.y);
			spr.scrollFactor.set(source.scrollFactor.x, source.scrollFactor.y);

			if (casted != null) {
				spr.skew.set(casted.skew.x, casted.skew.y);
				spr.transformMatrix = casted.transformMatrix;
				spr.matrixExposed = casted.matrixExposed;
				spr.animOffsets = casted.animOffsets.copy();
			}
		}
		return spr;
	}

	override function initVars() {
		super.initVars();
		animation = cast (animateAnim = new FlxAnimateController(this));
	}

	public override function update(elapsed:Float)
	{
		super.update(elapsed);

		// hate how it looks like but hey at least its optimized and fast  - Nex
		if (!debugMode && isAnimFinished()) {
			var name = getAnimName() + '-loop';
			if (hasAnimation(name))
				playAnim(name, null, lastAnimContext);
		}
	}

	public override function destroy()
	{
		super.destroy();
		anim = null;
		library = null;
		timeline = null;

		if (animOffsets != null) {
			for (i => v in animOffsets) {
				if (v != null) v.put();
				v.remove(key);
			}
			animOffsets = null;
		}
	}

	// Deprecated? - ralty
	public function loadSprite(path:String, Unique:Bool = false, Key:String = null)
	{
		frames = Paths.getFrames(path, true);
	}

	public function onPropertySet(property:String, value:Dynamic) {
		if (property.startsWith("velocity") || property.startsWith("acceleration"))
			moves = true;
	}

	private var countedBeat = 0;
	public function beatHit(curBeat:Int)
	{
		if (beatAnims.length > 0 && (curBeat + beatOffset) % beatInterval == 0)
		{
			if(skipNegativeBeats && curBeat < 0) return;
			// TODO: find a solution without countedBeat
			var anim = beatAnims[FlxMath.wrap(countedBeat++, 0, beatAnims.length - 1)];
			if (anim.name != null && anim.name != "null" && anim.name != "none")
				playAnim(anim.name, anim.forced);
		}
	}

	public function stepHit(curBeat:Int)
	{
	}

	public function measureHit(curMeasure:Int)
	{
	}

	public override function getScreenBounds(?newRect:FlxRect, ?camera:FlxCamera):FlxRect
	{
		__doPreZoomScaleProcedure(camera);
		var r = super.getScreenBounds(newRect, camera);
		__doPostZoomScaleProcedure();
		return r;
	}

	public override function doAdditionalMatrixStuff(matrix:FlxMatrix, camera:FlxCamera)
	{
		super.doAdditionalMatrixStuff(matrix, camera);
		matrix.translate(-camera.width / 2, -camera.height / 2);

		var requestedZoom = FlxMath.lerp(1, camera.zoom, zoomFactor);
		var diff = requestedZoom / camera.zoom;
		matrix.scale(diff, diff);
		matrix.translate(camera.width / 2, camera.height / 2);
	}

	public override function getScreenPosition(?point:FlxPoint, ?Camera:FlxCamera):FlxPoint
	{
		if (__shouldDoScaleProcedure())
		{
			__oldScrollFactor.set(scrollFactor.x, scrollFactor.y);
			var requestedZoom = FlxMath.lerp(initialZoom, camera.zoom, zoomFactor);
			var diff = requestedZoom / camera.zoom;

			scrollFactor.scale(1 / diff);

			var r = super.getScreenPosition(point, Camera);

			scrollFactor.set(__oldScrollFactor.x, __oldScrollFactor.y);

			return r;
		}
		return super.getScreenPosition(point, Camera);
	}

	// FLIXEL ANIMATE FUNCTIONALITY
	#if REGION
	override function draw() {
		if (!isAnimate) return super.draw();
		if (alpha == 0) return;

		if (shader != null && shader is FlxGraphicsShader)
			shader.setCamSize(_frame.frame.x, _frame.frame.y, _frame.frame.width, _frame.frame.height);

		for (camera in cameras) {
			if (!camera.visible || !camera.exists || !isOnScreen(camera)) continue;

			drawAnimate(camera);

			#if FLX_DEBUG
			FlxBasic.visibleCount++;
			#end
		}

		#if FLX_DEBUG
		if (FlxG.debugger.drawDebug) drawDebug();
		#end
	}

	function drawAnimate(camera:FlxCamera) {
		_matrix.identity();

		@:privateAccessbvar var bounds = timeline._bounds;
		_matrix.translate(-bounds.x, -bounds.y);

		var doFlipX = checkFlipX() != camera.flipX;
		var doFlipY = checkFlipY() != camera.flipY;

		_matrix.scale(doFlipX ? -1 : 1, doFlipY ? -1 : 1);
		_matrix.translate(doFlipX ? frame.sourceSize.x : 0, doFlipY ? frame.sourceSize.y : 0);
		_matrix.translate(-origin.x, -origin.y);

		if (frameOffsetAngle != null && frameOffsetAngle != angle) {
			var angleOff = (frameOffsetAngle - angle) * FlxAngle.TO_RAD;
			var cos = Math.cos(angleOff);
			var sin = Math.sin(angleOff);

			_matrix.rotateWithTrig(cos, -sin);
			_matrix.translate(-frameOffset.x, -frameOffset.y);
			_matrix.rotateWithTrig(cos, sin);
		}
		else
			_matrix.translate(-frameOffset.x, -frameOffset.y);

		_matrix.scale(scale.x, scale.y);

		if (matrixExposed) _matrix.concat(transformMatrix);
		else {
			if (angle != 0) {
				updateTrig();
				_matrix.rotateWithTrig(_cosAngle, _sinAngle);
			}
			updateSkewMatrix();
			_matrix.concat(_skewMatrix);
		}

		getScreenPosition(_point, camera).subtractPoint(offset).add(origin.x, origin.y);
		_matrix.translate(_point.x, _point.y);

		if (isPixelPerfectRender(camera)) {
			_matrix.tx = Math.floor(_matrix.tx);
			_matrix.ty = Math.floor(_matrix.ty);
		}

		doAdditionalMatrixStuff(_matrix, camera);

		timeline.currentFrame = animation.frameIndex;
		timeline.draw(camera, _matrix, colorTransform, blend, antialiasing, shader);
	}

	override function set_frames(frames:FlxFramesCollection):FlxFramesCollection {
		isAnimate = super.set_frames(frames) != null && (frames is FlxAnimateFrames);

		if (isAnimate) {
			library = cast frames;
			timeline = library.timeline;
			animateAnim.updateTimelineBounds();
		}
		else {
			library = null;
			timeline = null;
		}

		return frames;
	}

	override function get_numFrames():Int {
		if (!isAnimate) return super.get_numFrames();
		return animation.curAnim != null ? timeline.frameCount : 0;
	}
	#end

	// SCALING FUNCS
	#if REGION
	private inline function __shouldDoScaleProcedure()
		return zoomFactor != 1;

	static var __oldScrollFactor:FlxPoint = new FlxPoint();
	static var __oldScale:FlxPoint = new FlxPoint();
	var __skipZoomProcedure:Bool = false;

	private function __doPreZoomScaleProcedure(camera:FlxCamera)
	{
		if (__skipZoomProcedure = !__shouldDoScaleProcedure())
			return;
		__oldScale.set(scale.x, scale.y);
		var requestedZoom = FlxMath.lerp(initialZoom, camera.zoom, zoomFactor);
		var diff = requestedZoom * camera.zoom;

		scale.scale(diff);
	}

	private function __doPostZoomScaleProcedure()
	{
		if (__skipZoomProcedure)
			return;
		scale.set(__oldScale.x, __oldScale.y);
	}
	#end

	// OFFSETTING
	#if REGION
	public var animOffsets:Map<String, FlxPoint> = new Map<String, FlxPoint>();

	public function addOffset(name:String, x:Float = 0, y:Float = 0)
	{
		animOffsets[name] = FlxPoint.get(x, y);
	}

	public function switchOffset(anim1:String, anim2:String)
	{
		var old = animOffsets[anim1];
		animOffsets[anim1] = animOffsets[anim2];
		animOffsets[anim2] = old;
	}
	#end

	// PLAYANIM
	#if REGION
	public var lastAnimContext:PlayAnimContext = DANCE;

	public function playAnim(AnimName:String, ?Force:Null<Bool>, Context:PlayAnimContext = NONE, Reversed:Bool = false, Frame:Int = 0):Void
	{
		if (AnimName == null)
			return;

		if (Force == null) {
			var anim = animDatas.get(AnimName);
			Force = anim != null && anim.forced;
		}

		if (!animation.exists(AnimName) && !debugMode) return;
		animation.play(AnimName, Force, Reversed, Frame);

		var daOffset = getAnimOffset(AnimName);
		frameOffset.set(daOffset.x, daOffset.y);
		daOffset.putWeak();

		lastAnimContext = Context;
	}

	public inline function addAnim(name:String, prefix:String, frameRate:Float = 24, ?looped:Bool, ?forced:Bool, ?indices:Array<Int>, x:Float = 0, y:Float = 0, animType:XMLAnimType = NONE)
	{
		return XMLUtil.addAnimToSprite(this, {
			name: name,
			anim: prefix,
			fps: frameRate,
			loop: looped == null ? animType == LOOP : looped,
			animType: animType,
			x: x,
			y: y,
			indices: indices,
			forced: forced
		});
	}

	public inline function removeAnim(name:String) animation.remove(name);

	public function getAnim(name:String):FlxAnimation return animation.getByName(name);

	public inline function getAnimOffset(name:String)
	{
		if (animOffsets.exists(name))
			return animOffsets[name];
		return FlxPoint.weak(0, 0);
	}

	public inline function hasAnim(AnimName:String):Bool @:privateAccess
		return animation.exists(AnimName);

	public inline function getAnimName()
	{
		if (animation.curAnim != null)
			return animation.curAnim.name;

		return null;
	}

	public inline function isAnimReversed():Bool {
		return animation.curAnim != null ? animation.curAnim.reversed : false;
	}

	public inline function getNameList():Array<String> {
		return animation.getNameList();
	}

	public inline function stopAnim()
	{
		animation.stop();
	}

	public inline function isAnimFinished()
	{
		return animation.curAnim != null ? animation.curAnim.finished : true;
	}

	public inline function isAnimAtEnd() {
		return animation.curAnim != null ? animation.curAnim.isAtEnd : false;
	}

	// Backwards compat (the names used to be all different and it sucked, please lets use the same format in the future)  - Nex
	public inline function hasAnimation(AnimName:String) return hasAnim(AnimName);
	public inline function removeAnimation(name:String) return removeAnim(name);
	public inline function stopAnimation() return stopAnim();
	#end

	// Getter / Setters

	@:noCompletion private function set_beatInterval(v:Int) {
		if (v < 1)
			v = 1;

		return beatInterval = v;
	}
}
