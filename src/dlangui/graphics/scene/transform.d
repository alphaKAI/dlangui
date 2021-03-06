module dlangui.graphics.scene.transform;

import dlangui.core.math3d;

/// 3d transform: scale + translation + rotation
class Transform {
    protected bool _dirtyTransform = true;
    protected vec3 _scale = vec3(1.0f, 1.0f, 1.0f);
    protected vec3 _translation = vec3(0.0f, 0.0f, 0.0f);
    protected mat4 _rotation = mat4.identity;

    protected mat4 _matrix;

    this() {
        setIdentity();
    }

    /// get scale vector
    public @property ref const(vec3) scaling() const { return _scale; }
    /// get scale X
    public @property float scalingX() const { return _scale.x; }
    /// get scale Y
    public @property float scalingY() const { return _scale.y; }
    /// get scale Z
    public @property float scalingZ() const { return _scale.z; }
    
    /// set scale vector
    public @property void scaling(const ref vec3 value) { _scale = value; _dirtyTransform = true; }
    /// set scale vector x, y, z to the same value
    public @property void scaling(float value) { _scale.x = _scale.y = _scale.z = value; _dirtyTransform = true; }
    /// set scale X
    public @property void scalingX(float value) { _scale.x = value; _dirtyTransform = true; }
    /// set scale Y
    public @property void scalingY(float value) { _scale.y = value; _dirtyTransform = true; }
    /// set scale Z
    public @property void scalingZ(float value) { _scale.z = value; _dirtyTransform = true; }

    /// get translation vector
    public @property ref const(vec3) translation() const { return _translation; }
    /// get translation X
    public @property float translationX() const { return _translation.x; }
    /// get translation Y
    public @property float translationY() const { return _translation.y; }
    /// get translation Z
    public @property float translationZ() const { return _translation.z; }

    /// set translation vector
    public @property void translation(const ref vec3 value) { _translation = value; _dirtyTransform = true; }
    /// set translation vector x, y, z to the same value
    public @property void translation(float value) { _translation.x = _translation.y = _translation.z = value; _dirtyTransform = true; }
    /// set translation x
    public @property void translationX(float value) { _translation.x = value; _dirtyTransform = true; }
    /// set translation y
    public @property void translationY(float value) { _translation.y = value; _dirtyTransform = true; }
    /// set translation z
    public @property void translationZ(float value) { _translation.z = value; _dirtyTransform = true; }

    /// translate by vector
    public void translate(vec3 value) { _translation += value; _dirtyTransform = true; }
    /// translate X
    public void translateX(float value) { _translation.x += value; _dirtyTransform = true; }
    /// translate Y
    public void translateY(float value) { _translation.y += value; _dirtyTransform = true; }
    /// translate Z
    public void translateZ(float value) { _translation.z += value; _dirtyTransform = true; }

    /// scale by vector
    public void scale(vec3 value) { _scale.x *= value.x; _scale.y *= value.y; _scale.z *= value.z; _dirtyTransform = true; }
    /// scale all axis by the same values
    public void scale(float value) { _scale *= value; _dirtyTransform = true; }
    /// scale X
    public void scaleX(float value) { _scale.x *= value; _dirtyTransform = true; }
    /// scale Y
    public void scaleY(float value) { _scale.y *= value; _dirtyTransform = true; }
    /// scale Z
    public void scaleZ(float value) { _scale.z *= value; _dirtyTransform = true; }

    /// rotate around X axis
    public void rotateX(float angle) { _rotation.rotateX(angle); _dirtyTransform = true; }
    /// rotate around Y axis
    public void rotateY(float angle) { _rotation.rotateY(angle); _dirtyTransform = true; }
    /// rotate around Z axis
    public void rotateZ(float angle) { _rotation.rotateZ(angle); _dirtyTransform = true; }
    /// rotate around custom axis
    public void rotate(float angle, const ref vec3 axis) { _rotation.rotate(angle, axis); _dirtyTransform = true; }

    /// set transform to identity transform
    public void setIdentity() {
        _dirtyTransform = true;
        _scale = vec3(1.0f, 1.0f, 1.0f);
        _translation = vec3(0.0f, 0.0f, 0.0f);
        _rotation = mat4.identity;
    }

    /// get transform matrix, recalculates if needed
    public @property ref const(mat4) matrix() {
        if (_dirtyTransform) {
            _matrix = mat4.translation(_translation.x, _translation.y, _translation.z);
            _matrix = _matrix * _rotation;
            _matrix.scale(_scale.x, _scale.y, _scale.z);
            _dirtyTransform = false;
        }
        return _matrix;
    }

}
