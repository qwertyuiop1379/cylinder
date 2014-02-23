#import <lua/lua.h>
#import <lua/lauxlib.h>
#import "lua_UIView.h"

static int l_transform_rotate(lua_State *L);
static int l_transform_translate(lua_State *L);
static int l_transform_scale(lua_State *L);
static int l_set_transform(lua_State *L, UIView *self); //-1 = transform
static int l_get_transform(lua_State *L, UIView *self); //pushes transform to top of stack
static int l_uiview_index(lua_State *L);
static int l_uiview_setindex(lua_State *L);
static int l_uiview_len(lua_State *L);

int l_create_uiview_metatable(lua_State *L)
{
    luaL_newmetatable(L, "UIView");

    lua_pushcfunction(L, l_uiview_index);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, l_uiview_setindex);
    lua_setfield(L, -2, "__newindex");

    lua_pushcfunction(L, l_uiview_len);
    lua_setfield(L, -2, "__len");

    lua_pop(L, 1);

    return 0;
}


typedef unsigned int (*maxicons_func)(id, SEL);
typedef unsigned int (*maxrowcols_func)(id, SEL, UIDeviceOrientation);
int invoke_int(id self, SEL selector, BOOL use_orientation)
{
    IMP imp = [self methodForSelector:selector];
    if(use_orientation)
    {
        maxrowcols_func f = (maxrowcols_func)imp;
        return (int)f(self, selector, UIDevice.currentDevice.orientation);
    }
    else
    {
        maxicons_func f = (maxicons_func)imp;
        return (int)f(self, selector);
    }
}

typedef float (*float_func)(id, SEL);
float invoke_float(id self, SEL selector)
{
    return ((float_func)[self methodForSelector:selector])(self, selector);
}

static int l_uiview_index(lua_State *L)
{
    UIView *self = (UIView *)lua_touserdata(L, 1);
    if(lua_isnumber(L, 2)) //if it's a number, return the subview
    {
        int index = lua_tonumber(L, 2) - 1;
        if(index >= 0 && index < self.subviews.count)
        {
            push_view([self.subviews objectAtIndex:index]);
            return 1;
        }
    }
    else if(lua_isstring(L, 2))
    {
        const char *key = lua_tostring(L, 2);

        if(!strcmp(key, "subviews"))
        {
            lua_newtable(L);
            for(int i = 0; i < self.subviews.count; i++)
            {
                lua_pushnumber(L, i+1);
                push_view([self.subviews objectAtIndex:i]);
                lua_settable(L, -3);
            }
            return 1;
        }
        else if(!strcmp(key, "alpha"))
        {
            lua_pushnumber(L, self.alpha);
            return 1;
        }
        else if(!strcmp(key, "transform"))
        {
            return l_get_transform(L, self);
        }
        else if(!strcmp(key, "rotate"))
        {
            lua_pushcfunction(L, l_transform_rotate);
            return 1;
        }
        else if(!strcmp(key, "translate"))
        {
            lua_pushcfunction(L, l_transform_translate);
            return 1;
        }
        else if(!strcmp(key, "scale"))
        {
            lua_pushcfunction(L, l_transform_scale);
            return 1;
        }
        else if(!strcmp(key, "x"))
        {
            lua_pushnumber(L, self.frame.origin.x);
            return 1;
        }
        else if(!strcmp(key, "y"))
        {
            lua_pushnumber(L, self.frame.origin.y);
            return 1;
        }
        else if(!strcmp(key, "width"))
        {
            lua_pushnumber(L, self.frame.size.width/self.layer.transform.m11);
            return 1;
        }
        else if(!strcmp(key, "height"))
        {
            lua_pushnumber(L, self.frame.size.height/self.layer.transform.m22);
            return 1;
        }
        else if(!strcmp(key, "max_icons"))
        {
            SEL selector = @selector(maxIcons);
            if([self.class respondsToSelector:selector])
            {
                lua_pushnumber(L, invoke_int(self.class, selector, false));
                return 1;
            }
            else
                return 0;
        }
        else if(!strcmp(key, "max_columns"))
        {
            SEL selector = @selector(iconColumnsForInterfaceOrientation:);
            if([self.class respondsToSelector:selector])
            {
                lua_pushnumber(L, invoke_int(self.class, selector, true));
                return 1;
            }
            else
                return 0;
        }
        else if(!strcmp(key, "max_rows"))
        {
            SEL selector = @selector(iconRowsForInterfaceOrientation:);
            if([self.class respondsToSelector:selector])
            {
                lua_pushnumber(L, invoke_int(self.class, selector, true));
                return 1;
            }
            else
                return 0;
        }
        else if(!strcmp(key, "icon_spacing"))
        {
            SEL x = @selector(horizontalIconPadding);
            if(![self respondsToSelector:x])
            {
                x = @selector(horizontalIconSpace); //iOS 3
            }
            SEL y = @selector(verticalIconPadding);

            if([self respondsToSelector:x] && [self respondsToSelector:y])
            {
                lua_newtable(L);
                lua_pushstring(L, "x");
                lua_pushnumber(L, invoke_float(self, x));
                lua_settable(L, -3);
                lua_pushstring(L, "y");
                lua_pushnumber(L, invoke_float(self, y));
                lua_settable(L, -3);
                return 1;
            }
            else
            {
                return 0;
            }
        }
    }

    return 0;
}

static int l_uiview_setindex(lua_State *L)
{
    UIView *self = (UIView *)lua_touserdata(L, 1);
    if(lua_isstring(L, 2))
    {
        const char *key = lua_tostring(L, 2);
        if(!strcmp(key, "alpha"))
        {
            if(!lua_isnumber(L, 3))
                return luaL_error(L, "alpha must be a number");

            self.alpha = lua_tonumber(L, 3);
        }
        else if(!strcmp(key, "transform"))
        {
            lua_pushvalue(L, 3);
            int result = l_set_transform(L, self);
            lua_pop(L, 1);
            return result;
        }
    }
    return 0;
}

static int l_uiview_len(lua_State *L)
{
    UIView *self = (UIView *)lua_touserdata(L, 1);
    lua_pushnumber(L, self.subviews.count);
    return 1;
}


static int l_transform_rotate(lua_State *L)
{
    CHECK_UIVIEW(L, 1);

    UIView *self = (UIView *)lua_touserdata(L, 1);

    CATransform3D transform = self.layer.transform;
    float pitch = 0, yaw = 0, roll = 0;
    if(!lua_isnumber(L, 3))
        roll = 1;
    else
    {
        pitch = lua_tonumber(L, 3);
        yaw = lua_tonumber(L, 4);
        roll = lua_tonumber(L, 5);
    }

    if(fabs(pitch) > 0.01 || fabs(yaw) > 0.01)
        transform.m34 = -1/PERSPECTIVE_DISTANCE;

    transform = CATransform3DRotate(transform, lua_tonumber(L, 2), pitch, yaw, roll);

    self.layer.transform = transform;

    return 0;
}

static int l_transform_translate(lua_State *L)
{
    CHECK_UIVIEW(L, 1);

    UIView *self = (UIView *)lua_touserdata(L, 1);

    CATransform3D transform = self.layer.transform;
    float x = lua_tonumber(L, 2), y = lua_tonumber(L, 3), z = lua_tonumber(L, 4);
    float oldm34 = transform.m34;
    if(fabs(z) > 0.01)
        transform.m34 = -1/PERSPECTIVE_DISTANCE;
    transform = CATransform3DTranslate(transform, x, y, z);
    transform.m34 = oldm34;

    self.layer.transform = transform;

    return 0;
}

static int l_transform_scale(lua_State *L)
{
    CHECK_UIVIEW(L, 1);

    UIView *self = (UIView *)lua_touserdata(L, 1);

    CATransform3D transform = self.layer.transform;
    float x = lua_tonumber(L, 2);
    float y = x;
    float z = 1;
    if(lua_isnumber(L, 3))
        y = lua_tonumber(L, 3);
    if(lua_isnumber(L, 4))
        z = lua_tonumber(L, 4);
    float oldm34 = transform.m34;
    transform.m34 = -1/PERSPECTIVE_DISTANCE;
    transform = CATransform3DScale(transform, x, y, z);
    transform.m34 = oldm34;

    self.layer.transform = transform;

    return 0;
}

const static char *ERR_MALFORMED = "malformed transformation matrix";

static float POPA_T(lua_State *L, int index)
{
    lua_pushnumber(L, index);
    lua_gettable(L, -2);
    if(!lua_isnumber(L, -1))
        return luaL_error(L, ERR_MALFORMED);

    float result = lua_tonumber(L, -1);
    lua_pop(L, 1);
    return result;
}

#define CALL_TRANSFORM_MACRO(F, ...)\
    F(m11, ## __VA_ARGS__);\
    F(m12, ## __VA_ARGS__);\
    F(m13, ## __VA_ARGS__);\
    F(m14, ## __VA_ARGS__);\
    F(m21, ## __VA_ARGS__);\
    F(m22, ## __VA_ARGS__);\
    F(m23, ## __VA_ARGS__);\
    F(m24, ## __VA_ARGS__);\
    F(m31, ## __VA_ARGS__);\
    F(m32, ## __VA_ARGS__);\
    F(m33, ## __VA_ARGS__);\
    F(m34, ## __VA_ARGS__);\
    F(m41, ## __VA_ARGS__);\
    F(m42, ## __VA_ARGS__);\
    F(m43, ## __VA_ARGS__);\
    F(m44, ## __VA_ARGS__)

#define BASE_TRANSFORM_STEP(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_pushnumber(LUASTATE, TRANSFORM.M);\
    lua_settable(LUASTATE, -3)

int l_push_base_transform(lua_State *L)
{
    int i = 0;
    CALL_TRANSFORM_MACRO(BASE_TRANSFORM_STEP, L, i, CATransform3DIdentity);
    return 1;
}

#define FILL_TRANSFORM(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_gettable(LUASTATE, -3);\
    if(!lua_isnumber(LUASTATE, -1))\
        return luaL_error(LUASTATE, ERR_MALFORMED);\
    TRANSFORM.M = lua_tonumber(LUASTATE, -1);\
    lua_pop(LUASTATE, 1)

static int l_set_transform(lua_State *L, UIView *self) //-1 = transform
{
    if(!lua_istable(L, -1))
        return luaL_error(L, "transform must be a table");
    lua_len(L, -1);
    if(lua_tonumber(L, -1) != 16)
        return luaL_error(L, ERR_MALFORMED);
    lua_pop(L, 1);

    CATransform3D transform;
    int i = 0;
    CALL_TRANSFORM_MACRO(FILL_TRANSFORM, L, i, transform);
    self.layer.transform = transform;

    return 0;
}

#define PUSH_TRANSFORM(M, LUASTATE, I, TRANSFORM)\
    lua_pushnumber(LUASTATE, ++I);\
    lua_pushnumber(LUASTATE, TRANSFORM.M);\
    lua_settable(LUASTATE, -3)

static int l_get_transform(lua_State *L, UIView *self) //pushes transform to top of stack
{
    lua_newtable(L);
    int i = 0;
    CALL_TRANSFORM_MACRO(PUSH_TRANSFORM, L, i, self.layer.transform);
    return 1;
}
