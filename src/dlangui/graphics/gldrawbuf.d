// Written in the D programming language.

/**
This module contains opengl based drawing buffer implementation.

To enable OpenGL support, build with version(USE_OPENGL);

Synopsis:

----
import dlangui.graphics.gldrawbuf;

----

Copyright: Vadim Lopatin, 2014
License:   Boost License 1.0
Authors:   Vadim Lopatin, coolreader.org@gmail.com
*/
module dlangui.graphics.gldrawbuf;

public import dlangui.core.config;
static if (ENABLE_OPENGL):

import dlangui.graphics.drawbuf;
import dlangui.graphics.colors;
import dlangui.core.logger;
private import dlangui.graphics.glsupport;
private import std.algorithm;

interface GLConfigCallback {
    void saveConfiguration();
    void restoreConfiguration();
}

/// drawing buffer - image container which allows to perform some drawing operations
class GLDrawBuf : DrawBuf, GLConfigCallback {
    // width
    protected int _dx;
    // height
    protected int _dy;
    protected bool _framebuffer; // not yet supported
    protected uint _framebufferId; // not yet supported
    protected Scene _scene;

    /// get current scene (exists only between beforeDrawing() and afterDrawing() calls)
    @property Scene scene() { return _scene; }

    this(int dx, int dy, bool framebuffer = false) {
        _dx = dx;
        _dy = dy;
        _framebuffer = framebuffer;
        resetClipping();
    }

    /// returns current width
    @property override int width() { return _dx; }
    /// returns current height
    @property override int height() { return _dy; }

    override void saveConfiguration() {
    }
    override void restoreConfiguration() {
        glSupport.setOrthoProjection(Rect(0, 0, _dx, _dy), Rect(0, 0, _dx, _dy));
    }

    /// reserved for hardware-accelerated drawing - begins drawing batch
    override void beforeDrawing() {
        resetClipping();
		_alpha = 0;
        if (_scene !is null) {
            _scene.reset();
        }
        _scene = new Scene(this);
    }

    /// reserved for hardware-accelerated drawing - ends drawing batch
    override void afterDrawing() {
        glSupport.setOrthoProjection(Rect(0, 0, _dx, _dy), Rect(0, 0, _dx, _dy));
        _scene.draw();
        glSupport.flushGL();
        destroy(_scene);
        _scene = null;
    }

    /// resize buffer
    override void resize(int width, int height) {
        _dx = width;
        _dy = height;
        resetClipping();
    }

	/// draw custom OpenGL scene
	override void drawCustomOpenGLScene(Rect rc, OpenGLDrawableDelegate handler) {
		_scene.add(new CustomDrawnSceneItem(Rect(0, 0, width, height), rc, handler));
	}

    /// fill the whole buffer with solid color (no clipping applied)
    override void fill(uint color) {
        if (hasClipping) {
            fillRect(_clipRect, color);
            return;
        }
        assert(_scene !is null);
        _scene.add(new SolidRectSceneItem(Rect(0, 0, _dx, _dy), applyAlpha(color)));
    }
    /// fill rectangle with solid color (clipping is applied)
    override void fillRect(Rect rc, uint color) {
        assert(_scene !is null);
        color = applyAlpha(color);
        if (!isFullyTransparentColor(color) && applyClipping(rc))
            _scene.add(new SolidRectSceneItem(rc, color));
    }
    /// draw pixel at (x, y) with specified color
    override void drawPixel(int x, int y, uint color) {
        assert(_scene !is null);
		if (!_clipRect.isPointInside(x, y))
			return;
        color = applyAlpha(color);
        if (isFullyTransparentColor(color))
			return;
		_scene.add(new SolidRectSceneItem(Rect(x, y, x + 1, y + 1), color));
    }
	/// draw 8bit alpha image - usually font glyph using specified color (clipping is applied)
	override void drawGlyph(int x, int y, Glyph * glyph, uint color) {
        assert(_scene !is null);
		Rect dstrect = Rect(x,y, x + glyph.correctedBlackBoxX, y + glyph.blackBoxY);
		Rect srcrect = Rect(0, 0, glyph.correctedBlackBoxX, glyph.blackBoxY);
		//Log.v("GLDrawBuf.drawGlyph dst=", dstrect, " src=", srcrect, " color=", color);
        color = applyAlpha(color);
        if (!isFullyTransparentColor(color) && applyClipping(dstrect, srcrect)) {
            if (!glGlyphCache.get(glyph.id))
                glGlyphCache.put(glyph);
            _scene.add(new GlyphSceneItem(glyph.id, dstrect, srcrect, color, null));
        }
    }
    /// draw source buffer rectangle contents to destination buffer
    override void drawFragment(int x, int y, DrawBuf src, Rect srcrect) {
        assert(_scene !is null);
        Rect dstrect = Rect(x, y, x + srcrect.width, y + srcrect.height);
        //Log.v("GLDrawBuf.frawFragment dst=", dstrect, " src=", srcrect);
        if (applyClipping(dstrect, srcrect)) {
            if (!glImageCache.get(src.id))
                glImageCache.put(src);
            _scene.add(new TextureSceneItem(src.id, dstrect, srcrect, applyAlpha(0xFFFFFF), 0, null, 0));
        }
    }
    /// draw source buffer rectangle contents to destination buffer rectangle applying rescaling
    override void drawRescaled(Rect dstrect, DrawBuf src, Rect srcrect) {
        assert(_scene !is null);
        //Log.v("GLDrawBuf.frawRescaled dst=", dstrect, " src=", srcrect);
        if (applyClipping(dstrect, srcrect)) {
            if (!glImageCache.get(src.id))
                glImageCache.put(src);
            _scene.add(new TextureSceneItem(src.id, dstrect, srcrect, applyAlpha(0xFFFFFF), 0, null, 0));
        }
    }

	/// draw line from point p1 to p2 with specified color
	override void drawLine(Point p1, Point p2, uint colour) {
        assert(_scene !is null);
        if (!clipLine(_clipRect, p1, p2))
            return;
        _scene.add(new LineSceneItem(p1, p2, colour));
    }

    /// cleanup resources
    override void clear() {
        if (_framebuffer) {
            // TODO: delete framebuffer
        }
    }
    ~this() { clear(); }
}

/// base class for all drawing scene items.
class SceneItem {
    abstract void draw();
    /// when true, save configuration before drawing, and restore after drawing
    @property bool needSaveConfiguration() { return false; }
    /// when true, don't destroy item after drawing, since it's owned by some other component
    @property bool persistent() { return false; }
    void beforeDraw() { }
    void afterDraw() { }
}

class CustomSceneItem : SceneItem {
    private SceneItem[] _items;
    void add(SceneItem item) {
        _items ~= item;
    }
    override void draw() {
        foreach(SceneItem item; _items) {
            item.beforeDraw();
            item.draw();
            item.afterDraw();
        }
    }
    override @property bool needSaveConfiguration() { return true; }
}

/// Drawing scene (operations sheduled for drawing)
class Scene {
    private SceneItem[] _items;
    private GLConfigCallback _configCallback;
    this(GLConfigCallback configCallback) {
        _configCallback = configCallback;
        activeSceneCount++;
    }
    ~this() {
        activeSceneCount--;
    }
    /// add new scene item to scene
    void add(SceneItem item) {
        _items ~= item;
    }
    /// draws all scene items and removes them from list
    void draw() {
        foreach(SceneItem item; _items) {
            if (item.needSaveConfiguration) {
                _configCallback.saveConfiguration();
            }
            item.beforeDraw();
            item.draw();
            item.afterDraw();
            if (item.needSaveConfiguration) {
                _configCallback.restoreConfiguration();
            }
        }
        reset();
    }
    /// resets scene for new drawing - deletes all items
    void reset() {
        foreach(ref SceneItem item; _items) {
            if (!item.persistent) // only destroy items not owner by other components
                destroy(item);
            item = null;
        }
        _items.length = 0;
    }
}

private __gshared int activeSceneCount = 0;
bool hasActiveScene() {
    return activeSceneCount > 0;
}

enum MIN_TEX_SIZE = 64;
enum MAX_TEX_SIZE  = 4096;
private int nearestPOT(int n) {
    for (int i = MIN_TEX_SIZE; i <= MAX_TEX_SIZE; i *= 2) {
		if (n <= i)
			return i;
	}
	return MIN_TEX_SIZE;
}

/// object deletion listener callback function type
void onObjectDestroyedCallback(uint pobject) {
	glImageCache.onCachedObjectDeleted(pobject);
}

/// object deletion listener callback function type
void onGlyphDestroyedCallback(uint pobject) {
	glGlyphCache.onCachedObjectDeleted(pobject);
}

private __gshared GLImageCache glImageCache;
private __gshared GLGlyphCache glGlyphCache;

shared static this() {
    glImageCache = new GLImageCache();
    glGlyphCache = new GLGlyphCache();
}

void LVGLClearImageCache() {
	glImageCache.clear();
	glGlyphCache.clear();
}

/// OpenGL texture cache for ColorDrawBuf objects
private class GLImageCache {

    static class GLImageCacheItem {
        private GLImageCachePage _page;

        @property GLImageCachePage page() { return _page; }

        uint _objectId;
        Rect _rc;
        bool _deleted;

        this(GLImageCachePage page, uint objectId) { _page = page; _objectId = objectId; }
    };

    static class GLImageCachePage {
        private GLImageCache _cache;
        private int _tdx;
        private int _tdy;
        private ColorDrawBuf _drawbuf;
        private int _currentLine;
        private int _nextLine;
        private int _x;
        private bool _closed;
        private bool _needUpdateTexture;
        private Tex2D _texture;
        private int _itemCount;

        this(GLImageCache cache, int dx, int dy) {
            _cache = cache;
            Log.v("created image cache page ", dx, "x", dy);
            _tdx = nearestPOT(dx);
            _tdy = nearestPOT(dy);
            _itemCount = 0;
        }

        ~this() {
            if (_drawbuf) {
                destroy(_drawbuf);
                _drawbuf = null;
            }
            if (_texture && _texture.ID != 0) {
                destroy(_texture);
                _texture = null;
            }
        }

        void updateTexture() {
            if (_drawbuf is null)
                return; // no draw buffer!!!
            if (_texture is null || _texture.ID == 0) {
                _texture = new Tex2D();
                Log.d("updateTexture - new texture id=", _texture.ID);
                if (!_texture.ID)
                    return;
            }
            Log.d("updateTexture for image cache page - setting image ", _drawbuf.width, "x", _drawbuf.height, " tx=", _texture.ID);
            uint * pixels = _drawbuf.scanLine(0);
            if (!glSupport.setTextureImage(_texture, _drawbuf.width, _drawbuf.height, cast(ubyte*)pixels)) {
                destroy(_texture);
                _texture = null;
                return;
            }
            _needUpdateTexture = false;
            if (_closed) {
                destroy(_drawbuf);
                _drawbuf = null;
            }
        }

        void convertPixelFormat(GLImageCacheItem item) {
            Rect rc = item._rc;
            for (int y = rc.top - 1; y <= rc.bottom; y++) {
                uint * row = _drawbuf.scanLine(y);
                for (int x = rc.left - 1; x <= rc.right; x++) {
                    uint cl = row[x];
                    // invert A
                    cl ^= 0xFF000000;
                    // swap R and B
                    uint r = (cl & 0x00FF0000) >> 16;
                    uint b = (cl & 0x000000FF) << 16;
                    row[x] = (cl & 0xFF00FF00) | r | b;
                }
            }
        }

        GLImageCacheItem reserveSpace(uint objectId, int width, int height) {
            GLImageCacheItem cacheItem = new GLImageCacheItem(this, objectId);
            if (_closed)
                return null;

            // next line if necessary
            if (_x + width + 2 > _tdx) {
                // move to next line
                _currentLine = _nextLine;
                _x = 0;
            }
            // check if no room left for glyph height
            if (_currentLine + height + 2 > _tdy) {
                _closed = true;
                return null;
            }
            cacheItem._rc = Rect(_x + 1, _currentLine + 1, _x + width + 1, _currentLine + height + 1);
            if (height && width) {
                if (_nextLine < _currentLine + height + 2)
                    _nextLine = _currentLine + height + 2;
                if (!_drawbuf) {
                    _drawbuf = new ColorDrawBuf(_tdx, _tdy);
                    //_drawbuf.SetBackgroundColor(0x000000);
                    //_drawbuf.SetTextColor(0xFFFFFF);
                    _drawbuf.fill(0xFF000000);
                }
                _x += width + 1;
                _needUpdateTexture = true;
            }
            _itemCount++;
            return cacheItem;
        }
        int deleteItem(GLImageCacheItem item) {
            _itemCount--;
            return _itemCount;
        }
        GLImageCacheItem addItem(DrawBuf buf) {
            GLImageCacheItem cacheItem = reserveSpace(buf.id, buf.width, buf.height);
            if (cacheItem is null)
                return null;
            buf.onDestroyCallback = &onObjectDestroyedCallback;
            _drawbuf.drawImage(cacheItem._rc.left, cacheItem._rc.top, buf);
            convertPixelFormat(cacheItem);
            _needUpdateTexture = true;
            return cacheItem;
        }
        void drawItem(GLImageCacheItem item, Rect dstrc, Rect srcrc, uint color, uint options, Rect * clip, int rotationAngle) {
            //CRLog::trace("drawing item at %d,%d %dx%d <= %d,%d %dx%d ", x, y, dx, dy, srcx, srcy, srcdx, srcdy);
            if (_needUpdateTexture)
                updateTexture();
            if (_texture.ID != 0) {
                //rotationAngle = 0;
                int rx = dstrc.middlex;
                int ry = dstrc.middley;
                if (rotationAngle) {
                    //rotationAngle = 0;
                    //setRotation(rx, ry, rotationAngle);
                }
                // convert coordinates to cached texture
                srcrc.offset(item._rc.left, item._rc.top);
                if (clip) {
                    int srcw = srcrc.width();
                    int srch = srcrc.height();
                    int dstw = dstrc.width();
                    int dsth = dstrc.height();
                    if (dstw) {
                        srcrc.left += clip.left * srcw / dstw;
                        srcrc.right -= clip.right * srcw / dstw;
                    }
                    if (dsth) {
                        srcrc.top += clip.top * srch / dsth;
                        srcrc.bottom -= clip.bottom * srch / dsth;
                    }
                    dstrc.left += clip.left;
                    dstrc.right -= clip.right;
                    dstrc.top += clip.top;
                    dstrc.bottom -= clip.bottom;
                }
                if (!dstrc.empty)
                    glSupport.drawColorAndTextureRect(_texture, _tdx, _tdy, srcrc, dstrc, color, srcrc.width() != dstrc.width() || srcrc.height() != dstrc.height());
                //drawColorAndTextureRect(vertices, texcoords, color, _texture);

                if (rotationAngle) {
                    // unset rotation
                    glSupport.setRotation(rx, ry, 0);
                    //                glMatrixMode(GL_PROJECTION);
                    //                checkgl!glPopMatrix();
                }

            }
        }
        void close() {
            _closed = true;
            if (_needUpdateTexture)
                updateTexture();
        }
    }

    private GLImageCacheItem[uint] _map;
    private GLImageCachePage[] _pages;
    private GLImageCachePage _activePage;
    private int tdx;
    private int tdy;

    private void removePage(GLImageCachePage page) {
        if (_activePage == page)
            _activePage = null;
        foreach(i; 0 .. _pages.length)
            if (_pages[i] == page) {
                _pages.remove(i);
                break;
            }
        destroy(page);
    }

    private void updateTextureSize() {
        if (!tdx) {
            // TODO
            tdx = tdy = 1024; //getMaxTextureSize();
            if (tdx > 1024)
                tdx = tdy = 1024;
        }
    }

    this() {
    }
    ~this() {
        clear();
    }
    /// returns true if object exists in cache
    bool get(uint obj) {
        if (obj in _map)
            return true;
        return false;
    }
    /// put new object to cache
    void put(DrawBuf img) {
        updateTextureSize();
        GLImageCacheItem res = null;
        if (img.width <= tdx / 3 && img.height < tdy / 3) {
            // trying to reuse common page for small images
            if (_activePage is null) {
                _activePage = new GLImageCachePage(this, tdx, tdy);
                _pages ~= _activePage;
            }
            res = _activePage.addItem(img);
            if (!res) {
                _activePage = new GLImageCachePage(this, tdx, tdy);
                _pages ~= _activePage;
                res = _activePage.addItem(img);
            }
        } else {
            // use separate page for big image
            GLImageCachePage page = new GLImageCachePage(this, img.width, img.height);
            _pages ~= page;
            res = page.addItem(img);
            page.close();
        }
        _map[img.id] = res;
    }
    /// clears cache
    void clear() {
        foreach(i; 0 .. _pages.length) {
            destroy(_pages[i]);
            _pages[i] = null;
        }
        destroy(_pages);
        destroy(_map);
    }
    /// draw cached item
    void drawItem(uint objectId, Rect dstrc, Rect srcrc, uint color, int options, Rect * clip, int rotationAngle) {
        if (objectId in _map) {
            GLImageCacheItem item = _map[objectId];
            item.page.drawItem(item, dstrc, srcrc, color, options, clip, rotationAngle);
        }
    }
    /// handle cached object deletion, mark as deleted
    void onCachedObjectDeleted(uint objectId) {
        if (objectId in _map) {
            GLImageCacheItem item = _map[objectId];
            if (hasActiveScene()) {
                item._deleted = true;
            } else {
                int itemsLeft = item.page.deleteItem(item);
                //CRLog::trace("itemsLeft = %d", itemsLeft);
                if (itemsLeft <= 0) {
                    //CRLog::trace("removing page");
                    removePage(item.page);
                }
                _map.remove(objectId);
                destroy(item);
            }
        }
    }
    /// remove deleted items - remove page if contains only deleted items
    void removeDeletedItems() {
        uint[] list;
        foreach (GLImageCacheItem item; _map) {
            if (item._deleted)
                list ~= item._objectId;
        }
        foreach(i; 0 .. list.length) {
            onCachedObjectDeleted(list[i]);
        }
    }
}

private class GLGlyphCache {

    static class GLGlyphCacheItem {
        GLGlyphCachePage _page;
    public:
        @property GLGlyphCachePage page() { return _page; }
        uint _objectId;
        // image size
        Rect _rc;
        bool _deleted;
        this(GLGlyphCachePage page, uint objectId) { _page = page; _objectId = objectId; }
    };

    static class GLGlyphCachePage {
        private GLGlyphCache _cache;
        private int _tdx;
        private int _tdy;
        private ColorDrawBuf _drawbuf;
        private int _currentLine;
        private int _nextLine;
        private int _x;
        private bool _closed;
        private bool _needUpdateTexture;
        private Tex2D _texture;
        private int _itemCount;

        this(GLGlyphCache cache, int dx, int dy) {
            _cache = cache;
            Log.v("created glyph cache page ", dx, "x", dy);
            _tdx = nearestPOT(dx);
            _tdy = nearestPOT(dy);
            _itemCount = 0;
        }

        ~this() {
            if (_drawbuf) {
                destroy(_drawbuf);
                _drawbuf = null;
            }
            if (_texture.ID != 0) {
                destroy(_texture);
                _texture = null;
            }
        }

        void updateTexture() {
            if (_drawbuf is null)
                return; // no draw buffer!!!
            if (_texture is null || _texture.ID == 0) {
                _texture = new Tex2D();
                //Log.d("updateTexture - new texture ", _texture.ID);
                if (!_texture.ID)
                    return;
            }
            //Log.d("updateTexture for font glyph page - setting image ", _drawbuf.width, "x", _drawbuf.height, " tx=", _texture.ID);
            if (!glSupport.setTextureImage(_texture, _drawbuf.width, _drawbuf.height, cast(ubyte *)_drawbuf.scanLine(0))) {
                destroy(_texture);
                _texture = null;
                return;
            }
            _needUpdateTexture = false;
            if (_closed) {
                destroy(_drawbuf);
                _drawbuf = null;
            }
        }

        GLGlyphCacheItem reserveSpace(uint objectId, int width, int height) {
            GLGlyphCacheItem cacheItem = new GLGlyphCacheItem(this, objectId);
            if (_closed)
                return null;

            // next line if necessary
            if (_x + width + 2 > _tdx) {
                // move to next line
                _currentLine = _nextLine;
                _x = 0;
            }
            // check if no room left for glyph height
            if (_currentLine + height + 2 > _tdy) {
                _closed = true;
                return null;
            }
            cacheItem._rc = Rect(_x + 1, _currentLine + 1, _x + width + 1, _currentLine + height + 1);
            if (height && width) {
                if (_nextLine < _currentLine + height + 2)
                    _nextLine = _currentLine + height + 2;
                if (!_drawbuf) {
                    _drawbuf = new ColorDrawBuf(_tdx, _tdy);
                    //_drawbuf.SetBackgroundColor(0x000000);
                    //_drawbuf.SetTextColor(0xFFFFFF);
                    //_drawbuf.fill(0x00000000);
                    _drawbuf.fill(0xFF000000);
                }
                _x += width + 1;
                _needUpdateTexture = true;
            }
            _itemCount++;
            return cacheItem;
        }
        int deleteItem(GLGlyphCacheItem item) {
            _itemCount--;
            return _itemCount;
        }

        GLGlyphCacheItem addItem(Glyph * glyph) {
            GLGlyphCacheItem cacheItem = reserveSpace(glyph.id, glyph.correctedBlackBoxX, glyph.blackBoxY);
            if (cacheItem is null)
                return null;
            //_drawbuf.drawGlyph(cacheItem._rc.left, cacheItem._rc.top, glyph, 0xFFFFFF);
            _drawbuf.drawGlyphToTexture(cacheItem._rc.left, cacheItem._rc.top, glyph);
            _needUpdateTexture = true;
            return cacheItem;
        }

        void drawItem(GLGlyphCacheItem item, Rect dstrc, Rect srcrc, uint color, Rect * clip) {
            //CRLog::trace("drawing item at %d,%d %dx%d <= %d,%d %dx%d ", x, y, dx, dy, srcx, srcy, srcdx, srcdy);
            if (_needUpdateTexture)
                updateTexture();
            if (_texture.ID != 0) {
                // convert coordinates to cached texture
                srcrc.offset(item._rc.left, item._rc.top);
                if (clip) {
                    int srcw = srcrc.width();
                    int srch = srcrc.height();
                    int dstw = dstrc.width();
                    int dsth = dstrc.height();
                    if (dstw) {
                        srcrc.left += clip.left * srcw / dstw;
                        srcrc.right -= clip.right * srcw / dstw;
                    }
                    if (dsth) {
                        srcrc.top += clip.top * srch / dsth;
                        srcrc.bottom -= clip.bottom * srch / dsth;
                    }
                    dstrc.left += clip.left;
                    dstrc.right -= clip.right;
                    dstrc.top += clip.top;
                    dstrc.bottom -= clip.bottom;
                }
                if (!dstrc.empty) {
                    //Log.d("drawing glyph with color ", color);
                    glSupport.drawColorAndTextureRect(_texture, _tdx, _tdy, srcrc, dstrc, color, false);
                }

            }
        }
        void close() {
            _closed = true;
            if (_needUpdateTexture)
                updateTexture();
        }
    }

    GLGlyphCacheItem[uint] _map;
    GLGlyphCachePage[] _pages;
    GLGlyphCachePage _activePage;
    int tdx;
    int tdy;
    void removePage(GLGlyphCachePage page) {
        if (_activePage == page)
            _activePage = null;
        foreach(i; 0 .. _pages.length)
            if (_pages[i] == page) {
                _pages.remove(i);
                break;
            }
        destroy(page);
    }
    private void updateTextureSize() {
        if (!tdx) {
            // TODO
            tdx = tdy = 1024; //getMaxTextureSize();
            if (tdx > 1024)
                tdx = tdy = 1024;
        }
    }

    this() {
    }
    ~this() {
        clear();
    }
    /// check if item is in cache
    bool get(uint obj) {
        if (obj in _map)
            return true;
        return false;
    }
    /// put new item to cache
    void put(Glyph * glyph) {
        updateTextureSize();
        GLGlyphCacheItem res = null;
		if (_activePage is null) {
			_activePage = new GLGlyphCachePage(this, tdx, tdy);
			_pages ~= _activePage;
		}
		res = _activePage.addItem(glyph);
		if (!res) {
			_activePage = new GLGlyphCachePage(this, tdx, tdy);
			_pages ~= _activePage;
			res = _activePage.addItem(glyph);
		}
        _map[glyph.id] = res;
    }
    void clear() {
        foreach(i; 0 .. _pages.length) {
            destroy(_pages[i]);
            _pages[i] = null;
        }
        destroy(_pages);
        destroy(_map);
    }
    /// draw cached item
    void drawItem(uint objectId, Rect dstrc, Rect srcrc, uint color, Rect * clip) {
        GLGlyphCacheItem * item = objectId in _map;
        if (item)
            item.page.drawItem(*item, dstrc, srcrc, color, clip);
    }
    /// handle cached object deletion, mark as deleted
    void onCachedObjectDeleted(uint objectId) {
        if (objectId in _map) {
            GLGlyphCacheItem item = _map[objectId];
            if (hasActiveScene()) {
                item._deleted = true;
            } else {
                int itemsLeft = item.page.deleteItem(item);
                //CRLog::trace("itemsLeft = %d", itemsLeft);
                if (itemsLeft <= 0) {
                    //CRLog::trace("removing page");
                    removePage(item.page);
                }
                _map.remove(objectId);
                destroy(item);
            }
        }
    }
    /// remove deleted items - remove page if contains only deleted items
    void removeDeletedItems() {
        uint[] list;
        foreach (GLGlyphCacheItem item; _map) {
            if (item._deleted)
                list ~= item._objectId;
        }
        foreach(i; 0 .. list.length) {
            onCachedObjectDeleted(list[i]);
        }
    }
}





private class LineSceneItem : SceneItem {
private:
    Point _p1;
    Point _p2;
    uint _color;

public:
    this(Point p1, Point p2, uint color) {
        _p1 = p1;
        _p2 = p2;
        _color = color;
    }
    override void draw() {
        glSupport.drawLine(_p1, _p2, _color, _color);
    }
}

private class SolidRectSceneItem : SceneItem {
private:
    Rect _rc;
    uint _color;

public:
    this(Rect rc, uint color) {
        _rc = rc;
        _color = color;
    }
    override void draw() {
        glSupport.drawSolidFillRect(_rc, _color, _color, _color, _color);
    }
}

private class TextureSceneItem : SceneItem {
private:
	uint objectId;
    //CacheableObject * img;
    Rect dstrc;
    Rect srcrc;
	uint color;
	uint options;
	Rect * clip;
    int rotationAngle;

public:
	override void draw() {
		if (glImageCache)
            glImageCache.drawItem(objectId, dstrc, srcrc, color, options, clip, rotationAngle);
	}

    this(uint _objectId, Rect _dstrc, Rect _srcrc, uint _color, uint _options, Rect * _clip, int _rotationAngle)
	{
        objectId = _objectId;
        dstrc = _dstrc;
        srcrc = _srcrc;
        color = _color;
        options = _options;
        clip = _clip;
        rotationAngle = _rotationAngle;
	}
}

private class GlyphSceneItem : SceneItem {
private:
	uint objectId;
    Rect dstrc;
    Rect srcrc;
	uint color;
	Rect * clip;

public:
	override void draw() {
		if (glGlyphCache)
            glGlyphCache.drawItem(objectId, dstrc, srcrc, color, clip);
	}
    this(uint _objectId, Rect _dstrc, Rect _srcrc, uint _color, Rect * _clip)
	{
        objectId = _objectId;
        dstrc = _dstrc;
        srcrc = _srcrc;
        color = _color;
        clip = _clip;
	}
}

private class CustomDrawnSceneItem : SceneItem {
private:
	Rect _windowRect;
	Rect _rc;
	OpenGLDrawableDelegate _handler;

public:
	this(Rect windowRect, Rect rc, OpenGLDrawableDelegate handler) {
		_windowRect = windowRect;
		_rc = rc;
		_handler = handler;
	}
	override void draw() {
		if (_handler) {
			glSupport.setOrthoProjection(_windowRect, _rc);
			_handler(_windowRect, _rc);
			glSupport.setOrthoProjection(_windowRect, _windowRect);
		}
	}
}


/// GL Texture object from image
static class GLTexture {
	protected int _dx;
	protected int _dy;
	protected int _tdx;
	protected int _tdy;

	@property Point imageSize() {
		return Point(_dx, _dy);
	}

	protected Tex2D _texture;
	/// returns texture object
	@property Tex2D texture() { return _texture; }
	/// returns texture id
	@property uint textureId() { return _texture ? _texture.ID : 0; }

	bool isValid() {
		return _texture && _texture.ID;
	}
	/// image coords to UV
	float[2] uv(int x, int y) {
		float[2] res;
		res[0] = x * cast(float) _dx / _tdx;
		res[1] = y * cast(float) _dy / _tdy;
		return res;
	}
	float[2] uv(Point pt) {
		float[2] res;
		res[0] = pt.x * cast(float) _dx / _tdx;
		res[1] = pt.y * cast(float) _dy / _tdy;
		return res;
	}
	/// return UV coords for bottom right corner
	float[2] uv() {
		return uv(_dx, _dy);
	}

	this(string resourceId) {
		import dlangui.graphics.resources;
		string path = drawableCache.findResource(resourceId);
		this(cast(ColorDrawBuf)imageCache.get(path));
	}

	this(ColorDrawBuf buf) {
		if (buf) {
			_dx = buf.width;
			_dy = buf.height;
			_tdx = nearestPOT(_dx);
			_tdy = nearestPOT(_dy);
			_texture = new Tex2D();
			if (!_texture.ID)
				return;
			uint * pixels = buf.scanLine(0);
			if (!glSupport.setTextureImage(_texture, buf.width, buf.height, cast(ubyte*)pixels)) {
				destroy(_texture);
				_texture = null;
				return;
			}
		}
	}
	~this() {
		if (_texture && _texture.ID != 0) {
			destroy(_texture);
			_texture = null;
		}
	}
}
