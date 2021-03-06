import 'package:expandable/expandable.dart';
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import 'package:flutter_screenutil/flutter_screenutil.dart';
import "package:photo_view/photo_view.dart";
import "package:photo_view/photo_view_gallery.dart";

import 'package:sitescape/services/classes.dart';
import 'package:sitescape/services/ui.dart';

/* The Preview Page is for photo inspection and interaction; the user can
   zoom, pinch and scroll through a task"s gallery
   
   selection -> UserSelection: For passing site, sub, sec, task parameters
   startIndex -> int: Used for initialising which image should be shown first 
*/
class PreviewCloudPage extends StatefulWidget {
  final Task task;
  final List<Future<NetworkTaskImage>> list;
  final int startIndex;

  const PreviewCloudPage({
    Key key,
    @required this.task,
    @required this.list,
    this.startIndex,
  }) : super(key: key);

  @override
  _PreviewCloudScreenState createState() => _PreviewCloudScreenState(this.task);
}

/* State for PreviewScreen */
class _PreviewCloudScreenState extends State<PreviewCloudPage> {
  final Task task;
  _PreviewCloudScreenState(this.task);

  List<NetworkTaskImage> _images;

  int _currentPage;

  // To allow indication of initial page
  PageController _pageController;
  // Array of task images in the gallery

  @override
  void initState() {
    super.initState();
    // To allow indication of initial page
    _pageController = new PageController(initialPage: widget.startIndex);

    _images = List<NetworkTaskImage>.filled(widget.list.length, null);
    _currentPage = widget.startIndex;

    Future.delayed(Duration(milliseconds: 200)).then((onValue) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    _pageController.dispose();
  }

  Widget build(BuildContext context) {
    // Reset all photos with each build as delete operations may have happened
    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      backgroundColor: Colors.black,
      body: Stack(
        children: <Widget>[
          showPreviewGallery(),
          showBackFloatButton(),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        notchMargin: 12.0,
        elevation: 0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Icon(Icons.camera_alt, color: Colors.transparent, size: 36),
          ],
        ),
        color: Colors.transparent,
        shape: CircularNotchedRectangle(),
      ),
    );
  }

  /* Main content of the page, using PhotoViewGallery on allPhotos */
  Widget showPreviewGallery() {
    return Stack(children: [
      Center(
        child: Container(
          child: PhotoViewGallery.builder(
            pageController: _pageController,
            scrollPhysics: const BouncingScrollPhysics(),
            onPageChanged: ((index) {
              setState(() {
                _currentPage = index;
              });
            }),
            builder: (BuildContext context, int index) {
              return PhotoViewGalleryPageOptions.customChild(
                child: FutureBuilder(
                    future: widget.list[index],
                    builder: (BuildContext context,
                        AsyncSnapshot<NetworkTaskImage> snapshot) {
                      NetworkTaskImage netTask = snapshot.data;
                      if (!snapshot.hasData) {
                        return Container();
                      } else {
                        _images[index] = snapshot.data;
                      }

                      return Column(children: [
                        Expanded(
                          child: FadeInImage(
                            fit: BoxFit.fitWidth,
                            fadeInDuration: Duration(milliseconds: 100),
                            fadeOutDuration: Duration(milliseconds: 100),
                            placeholder: netTask.image,
                            image: netTask.getFullImage(),
                          ),
                        ),
                      ]);
                    }),
                initialScale: PhotoViewComputedScale.contained * 1,
                minScale: PhotoViewComputedScale.contained * 1,
                maxScale: PhotoViewComputedScale.covered * 10,
              );
            },
            itemCount: widget.list.length,
          ),
        ),
      ),
      Align(
          alignment: Alignment.bottomCenter,
          child: Column(
            children: [Expanded(child: Container()), showDescription()],
          ))
    ]);
  }

  /* Below task header at top */
  Widget showDescription() {
    NetworkTaskImage netTask = _images[_currentPage];
    if (netTask == null) {
      return Container();
    }

    Color color;
    String header;
    AssetImage image;

    if (netTask.approved) {
      color = Colors.green.withOpacity(0.15);
      header = " This photo has been approved";
      image = AssetImage("images/icons/icon_check.png");
    } else if (netTask.rejected) {
      color = Colors.red.withOpacity(0.15);
      header = " This photo has been rejected";
      image = AssetImage("images/icons/icon_status_alert.png");
    } else {
      color = Colors.grey.withOpacity(0.1);
      header = " This photo is pending for approval";
      image = AssetImage("images/icons/icon_pending.png");
    }

    return Container(
      width: MediaQuery.of(context).size.width,
      color: color,
      padding: EdgeInsets.only(left: 12, right: 12, bottom: 16, top: 12),
      child: ExpandablePanel(
        // ignore: deprecated_member_use
        headerAlignment: ExpandablePanelHeaderAlignment.center,
        // ignore: deprecated_member_use
        iconColor: Colors.white,
        // ignore: deprecated_member_use
        tapHeaderToExpand: true,
        // ignore: deprecated_member_use
        tapBodyToCollapse: true,
        header: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ImageIcon(image, size: 18, color: Colors.white),
            SizedBox(width: 6),
            Text(
              header,
              style: TextStyle(
                fontSize: ScreenUtil().setSp(42),
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: "Quicksand",
              ),
            ),
          ],
        ),
        collapsed: Text(
            netTask.message == null || netTask.message == ""
                ? "No user feedback attached"
                : "\"" + netTask.message + "\"",
            textAlign: TextAlign.justify,
            maxLines: 3,
            style: TextStyle(
                fontSize: ScreenUtil().setSp(36),
                color: Colors.white54,
                fontStyle: netTask.message == null || netTask.message == ""
                    ? FontStyle.italic
                    : FontStyle.normal),
            softWrap: true,
            overflow: TextOverflow.ellipsis),
        expanded: Text(
          netTask.message == null || netTask.message == ""
              ? "No user feedback attached"
              : "\"" + netTask.message + "\"",
          textAlign: TextAlign.justify,
          style: TextStyle(
              fontSize: ScreenUtil().setSp(36),
              color: Colors.white54,
              fontStyle: netTask.message == null || netTask.message == ""
                  ? FontStyle.italic
                  : FontStyle.normal),
          softWrap: true,
        ),
      ),
    );
  }
}
