/*
 * GStreamer
 * Copyright (C) <1999> Erik Walthinsen <omega@cse.ogi.edu>
 * Copyright (C) <2003> David Schleef <ds@schleef.org>
 * Copyright (C) <2012> Mikhail Durnev <mdurnev@rhonda.ru>
 * Copyright (C) <2014> Mikhail Durnev <mikhail_durnev@mentor.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 * Alternatively, the contents of this file may be used under the
 * GNU Lesser General Public License Version 2.1 (the "LGPL"), in
 * which case the following provisions apply instead of the ones
 * mentioned above:
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 59 Temple Place - Suite 330,
 * Boston, MA 02111-1307, USA.
 */

/**
 * SECTION:element-plugin
 *
 * FIXME:Describe plugin here.
 *
 * <refsect2>
 * <title>Example launch line</title>
 * |[
 * gst-launch -v -m videotestsrc ! plugin ! autovideosink
 * ]|
 * </refsect2>
 */
 
#ifdef HAVE_CONFIG_H
#include "../../common/config.h"
#endif

#include <gst/gst.h>
#include <gst/video/video.h>
#include <gst/video/gstvideofilter.h>
#include <string.h>

#define CUDA_CHECK_RETURN(value) {                                          \
    cudaError_t stat = value;                                        \
    if (stat != cudaSuccess) {                                       \
        GST_DEBUG("Error %s at line %d in file %s\n",                 \
                cudaGetErrorString(stat), __LINE__, __FILE__);       \
    } }

typedef unsigned int uint32_t;

#define PLAGIN_NAME "cudagradient"
#define PLAGIN_SHORT_DESCRIPTION "CUDA gradient Filter"

GST_DEBUG_CATEGORY_STATIC (gst_plugin_template_debug);
#define GST_CAT_DEFAULT gst_plugin_template_debug

typedef struct _GstPlugincudagradient GstPlugincudagradient;
typedef struct _GstPlugincudagradientClass GstPlugincudagradientClass;

#define GST_TYPE_PLUGIN_TEMPLATE \
  (gst_plugin_template_get_type())
#define GST_PLUGIN_TEMPLATE(obj) \
  (G_TYPE_CHECK_INSTANCE_CAST((obj),GST_TYPE_PLUGIN_TEMPLATE,GstPlugincudagradient))
#define GST_PLUGIN_TEMPLATE_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_CAST((klass),GST_TYPE_PLUGIN_TEMPLATE,GstPlugincudagradientClass))
#define GST_IS_PLUGIN_TEMPLATE(obj) \
  (G_TYPE_CHECK_INSTANCE_TYPE((obj),GST_TYPE_PLUGIN_TEMPLATE))
#define GST_IS_PLUGIN_TEMPLATE_CLASS(klass) \
  (G_TYPE_CHECK_CLASS_TYPE((klass),GST_TYPE_PLUGIN_TEMPLATE))

#define RECEPTIVE_FIELD_SIZE 8
#define RECEPTIVE_FIELD_MAX_VALUE 46

const int receptive_field_mask[RECEPTIVE_FIELD_SIZE * RECEPTIVE_FIELD_SIZE] =
    { 0,  0,  1,  1,  1,  1,  0,  0,
      0,  1,  1,  2,  2,  1,  1,  0,
      1,  1,  2,  3,  3,  2,  1,  1,
      1,  2,  3,  4,  4,  3,  2,  1,
     -1, -2, -3, -4, -4, -3, -2, -1,
     -1, -1, -2, -3, -3, -2, -1, -1,
      0, -1, -1, -2, -2, -1, -1,  0,
      0,  0, -1, -1, -1, -1,  0,  0
    };

__device__ __constant__ int c_receptive_field_mask[RECEPTIVE_FIELD_SIZE][RECEPTIVE_FIELD_SIZE];

struct _GstPlugincudagradient
{
  GstVideoFilter videofilter;

  gint width;
  gint height;
};

struct _GstPlugincudagradientClass
{
  GstVideoFilterClass parent_class;
};


enum
{
  /* FILL ME */
  LAST_SIGNAL
};

enum
{
  PROP_0
};

/* debug category for fltering log messages
 */
#define DEBUG_INIT(bla) \
  GST_DEBUG_CATEGORY_INIT (gst_plugin_template_debug, PLAGIN_NAME, 0, PLAGIN_SHORT_DESCRIPTION);

GST_BOILERPLATE_FULL (GstPlugincudagradient, gst_plugin_template,
    GstVideoFilter, GST_TYPE_VIDEO_FILTER, DEBUG_INIT);

static void gst_plugin_template_set_property (GObject * object,
    guint prop_id, const GValue * value, GParamSpec * pspec);
static void gst_plugin_template_get_property (GObject * object,
    guint prop_id, GValue * value, GParamSpec * pspec);
static void gst_plugin_template_finalize (GObject * object);

static gboolean gst_plugin_template_set_caps (GstBaseTransform * bt,
    GstCaps * incaps, GstCaps * outcaps);
//static GstFlowReturn gst_plugin_template_filter (GstBaseTransform * bt,
//    GstBuffer * outbuf, GstBuffer * inbuf);
static GstFlowReturn
gst_plugin_template_filter_inplace (GstBaseTransform * base_transform,
    GstBuffer * buf);

#define ALLOWED_CAPS_STRING \
    GST_VIDEO_CAPS_BGRx

static GstStaticPadTemplate gst_video_filter_src_template =
GST_STATIC_PAD_TEMPLATE ("src",
    GST_PAD_SRC,
    GST_PAD_ALWAYS,
    GST_STATIC_CAPS (ALLOWED_CAPS_STRING)
    );

static GstStaticPadTemplate gst_video_filter_sink_template =
GST_STATIC_PAD_TEMPLATE ("sink",
    GST_PAD_SINK,
    GST_PAD_ALWAYS,
    GST_STATIC_CAPS (ALLOWED_CAPS_STRING)
    );

/* GObject method implementations */

static void
gst_plugin_template_base_init (gpointer klass)
{
  GstElementClass *element_class = GST_ELEMENT_CLASS (klass);
  GstVideoFilterClass *videofilter_class = GST_VIDEO_FILTER_CLASS (klass);
  GstCaps *caps;

  gst_element_class_set_details_simple (element_class,
    PLAGIN_NAME,
    "Filter/Effect/Video",
    "gradient",
    "Mikhail Durnev <mikhail_durnev@mentor.com>");

  gst_element_class_add_pad_template (element_class,
      gst_static_pad_template_get (&gst_video_filter_sink_template));
  gst_element_class_add_pad_template (element_class,
      gst_static_pad_template_get (&gst_video_filter_src_template));
}

static void
gst_plugin_template_class_init (GstPlugincudagradientClass * klass)
{
  GObjectClass *gobject_class;
  GstBaseTransformClass *btrans_class;
  GstVideoFilterClass *video_filter_class;

  gobject_class = (GObjectClass *) klass;
  btrans_class = (GstBaseTransformClass *) klass;
  video_filter_class = (GstVideoFilterClass *) klass;

  gobject_class->set_property = gst_plugin_template_set_property;
  gobject_class->get_property = gst_plugin_template_get_property;
  gobject_class->finalize = gst_plugin_template_finalize;

  btrans_class->set_caps = gst_plugin_template_set_caps;
  btrans_class->transform = NULL;
  btrans_class->transform_ip = gst_plugin_template_filter_inplace;
}

static void
gst_plugin_template_init (GstPlugincudagradient * plugin_template,
    GstPlugincudagradientClass * g_class)
{
  CUDA_CHECK_RETURN(cudaMemcpyToSymbol(c_receptive_field_mask, receptive_field_mask, RECEPTIVE_FIELD_SIZE * RECEPTIVE_FIELD_SIZE * sizeof(int)));
  GST_DEBUG ("init");
}

static void
gst_plugin_template_set_property (GObject * object, guint prop_id,
    const GValue * value, GParamSpec * pspec)
{
  GstPlugincudagradient *filter = GST_PLUGIN_TEMPLATE (object);

  GST_OBJECT_LOCK (filter);
  switch (prop_id) {
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
  GST_OBJECT_UNLOCK (filter);
}

static void
gst_plugin_template_get_property (GObject * object, guint prop_id,
    GValue * value, GParamSpec * pspec)
{
  GstPlugincudagradient *filter = GST_PLUGIN_TEMPLATE (object);

  GST_OBJECT_LOCK (filter);
  switch (prop_id) {
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
  GST_OBJECT_UNLOCK (filter);
}

static void
gst_plugin_template_finalize (GObject * object)
{
  GstPlugincudagradient *filter = GST_PLUGIN_TEMPLATE (object);

  //G_OBJECT_CLASS (object)->finalize (object);

  GST_DEBUG("finalize");
}


static gboolean
gst_plugin_template_set_caps (GstBaseTransform * bt,
    GstCaps * incaps, GstCaps * outcaps)
{
  GstPlugincudagradient *plugin_template;
  GstStructure *structure = NULL;
  gboolean ret = FALSE;

  plugin_template = GST_PLUGIN_TEMPLATE (bt);

  structure = gst_caps_get_structure (incaps, 0);

  GST_OBJECT_LOCK (plugin_template);
  if (gst_structure_get_int (structure, "width", &plugin_template->width) &&
      gst_structure_get_int (structure, "height", &plugin_template->height))
  {
    /* Check width and height and modify other plugin_template members accordingly */
    ret = TRUE;
  }
  GST_OBJECT_UNLOCK (plugin_template);

  return ret;
}

__global__ void video_filter(cudaTextureObject_t in, uchar4* out, size_t pitch, int width, int height)
{
    unsigned int x = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned int y = blockIdx.y * blockDim.y + threadIdx.y;

    __shared__ int s_receptive_field_mask[RECEPTIVE_FIELD_SIZE][RECEPTIVE_FIELD_SIZE];
    if (threadIdx.x < RECEPTIVE_FIELD_SIZE && threadIdx.y < RECEPTIVE_FIELD_SIZE)
    {
        s_receptive_field_mask[threadIdx.x][threadIdx.y] = c_receptive_field_mask[threadIdx.x][threadIdx.y];
    }
    __syncthreads();

    int vert = 0;
    int horz = 0;
    int i, j;
    for (i = 0; i < RECEPTIVE_FIELD_SIZE; i++)
    {
        for (j = 0; j < RECEPTIVE_FIELD_SIZE; j++)
        {
            uchar4 p = tex2D<uchar4>(in, x + j, y + i);
            int lum = p.x + 6 * p.y + 3 * p.z;
            vert += lum * s_receptive_field_mask[j][i];
            horz += lum * s_receptive_field_mask[i][j];

        }
    }
    vert = vert / (RECEPTIVE_FIELD_MAX_VALUE * 20) + 128;
    horz = horz / (RECEPTIVE_FIELD_MAX_VALUE * 20) + 128;

    uchar4 v = {128, vert, horz, 0};

    *(uchar4*)((char*)out + (pitch * y + x * sizeof(uchar4))) = v;
}

static GstFlowReturn
gst_plugin_template_filter_inplace (GstBaseTransform * base_transform,
    GstBuffer * buf)
{
  GstPlugincudagradient *plugin_template = GST_PLUGIN_TEMPLATE (base_transform);
  GstVideoFilter *videofilter = GST_VIDEO_FILTER (base_transform);

  gint width = plugin_template->width;
  gint height = plugin_template->height;

  unsigned long long *in = (unsigned long long *) GST_BUFFER_DATA (buf);
  /*
   * in[0] - device pointer to the allocated memory
   * in[1] - pitch in bytes
   * in[2] - texture object
   * in[3] - device memory allocated for image processing
   * in[4] - pitch in bytes
   * in[5] - texture object
   */

  dim3 dimBlock(16, 16);
  dim3 dimGrid((width + dimBlock.x - 1) / dimBlock.x,
               (height + dimBlock.y - 1) / dimBlock.y);

  video_filter<<<dimGrid, dimBlock>>>((cudaTextureObject_t)in[2], (uchar4*)in[3], (size_t)in[4], width, height);

  CUDA_CHECK_RETURN(cudaThreadSynchronize());
  CUDA_CHECK_RETURN(cudaGetLastError());

  // Swap buffers
  int i;
  for (i = 0; i < 3; i++)
  {
      unsigned long long x = in[i];
      in[i] = in[i + 3];
      in[i + 3] = x;
  }

  return GST_FLOW_OK;
}

static gboolean
plugin_init (GstPlugin * plugin)
{
  return gst_element_register (plugin, PLAGIN_NAME, GST_RANK_NONE,
      GST_TYPE_PLUGIN_TEMPLATE);
}

/* gstreamer looks for this structure to register plugins
 */
GST_PLUGIN_DEFINE (
    GST_VERSION_MAJOR,
    GST_VERSION_MINOR,
    PLAGIN_NAME,
    PLAGIN_SHORT_DESCRIPTION,
    plugin_init,
    VERSION, "LGPL",
    "GStreamer",
    "http://gstreamer.net/"
);
