#include <jni.h>
#include <cstdint>
#include <vector>
#include <hb.h>
#include <hb-ot.h>

extern "C" JNIEXPORT jintArray JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeHarfBuzzShape(
        JNIEnv *env,jclass,jstring jText,jstring jFontPath,jint pixelSize,jboolean rtl){
    if(!jText||!jFontPath)return nullptr;
    const char*text=env->GetStringUTFChars(jText,nullptr);
    const char*fp  =env->GetStringUTFChars(jFontPath,nullptr);
    hb_blob_t*blob=hb_blob_create_from_file_or_fail(fp);
    if(!blob){env->ReleaseStringUTFChars(jText,text);env->ReleaseStringUTFChars(jFontPath,fp);return nullptr;}
    hb_face_t*face=hb_face_create(blob,0);
    hb_font_t*font=hb_font_create(face);
    int scale=pixelSize>0?pixelSize:32;
    hb_font_set_scale(font,scale,scale); hb_ot_font_set_funcs(font);
    hb_buffer_t*buf=hb_buffer_create();
    hb_buffer_add_utf8(buf,text,-1,0,-1);
    hb_buffer_set_direction(buf,rtl?HB_DIRECTION_RTL:HB_DIRECTION_LTR);
    hb_buffer_set_script(buf,HB_SCRIPT_ARABIC);
    hb_buffer_set_language(buf,hb_language_from_string("ar",-1));
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font,buf,nullptr,0);
    unsigned gc=0; hb_glyph_info_t*gi=hb_buffer_get_glyph_infos(buf,&gc);
    std::vector<jint> flat((size_t)gc*2);
    for(unsigned i=0;i<gc;++i){flat[i*2]=(jint)gi[i].codepoint;flat[i*2+1]=(jint)gi[i].cluster;}
    jintArray r=env->NewIntArray((jsize)flat.size());
    if(r&&!flat.empty())env->SetIntArrayRegion(r,0,(jsize)flat.size(),flat.data());
    hb_buffer_destroy(buf);hb_font_destroy(font);hb_face_destroy(face);hb_blob_destroy(blob);
    env->ReleaseStringUTFChars(jText,text); env->ReleaseStringUTFChars(jFontPath,fp);
    return r;
}
extern "C" JNIEXPORT jstring JNICALL
Java_com_awlqy_terminal_core_ArabicShaper_nativeHarfBuzzVersion(JNIEnv*env,jclass){
    const char*v=hb_version_string(); return env->NewStringUTF(v?v:"");
}
