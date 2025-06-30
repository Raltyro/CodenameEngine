package funkin.backend;

import flixel.math.FlxAngle;

class FlxAnimate extends animate.FlxAnimate {
	override function drawAnimate(camera:FlxCamera) {
		_matrix.identity();

		if (!useLegacyBounds) {
			@:privateAccess var bounds = timeline._bounds;
			_matrix.translate(-bounds.x, -bounds.y);
		}

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

		if (angle != 0) {
			updateTrig();
			_matrix.rotateWithTrig(_cosAngle, _sinAngle);
		}

		if (skew.x != 0 || skew.y != 0) {
			updateSkew();
			@:privateAccess _matrix.concat(animate.FlxAnimate._skewMatrix);
		}

		getScreenPosition(_point, camera).subtractPoint(offset).add(origin.x, origin.y);
		_matrix.translate(_point.x, _point.y);

		if (renderStage) drawStage(camera);

		timeline.currentFrame = animation.frameIndex;
		timeline.draw(camera, _matrix, colorTransform, blend, antialiasing, shader);
	}
}