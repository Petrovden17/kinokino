import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/media_item.dart';
import '../services/tmdb_service.dart';
import '../services/profile_service.dart';
import '../services/settings_service.dart';
import '../widgets/poster_card.dart';
import 'profiles_screen.dart';
import 'settings_screen.dart';
import 'library_screen.dart';
import 'about_screen.dart';
import 'media_details_screen.dart';
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key,required this.profileService,required this.settingsService});
  final ProfileService profileService;final SettingsService settingsService;
  @override State<HomeScreen> createState()=>_HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen>{
  final _tmdb=TmdbService();final _search=TextEditingController();final _scroll=ScrollController();int _page=1;bool _hasMore=true;bool _loadingMore=false;
  List<MediaItem> _items=[];List<Map<String,dynamic>> _genres=[];
  bool _loading=false;String? _error;String _type='movie';String _sort='popularity.desc';int? _genreId;double _minRating=0;
  String get _apiType => _type=='tv'||_type=='animated_tv'?'tv':'movie';
  int? get _effectiveGenre => _type=='animation'||_type=='animated_tv'?16:_genreId;
  @override void initState(){super.initState();_scroll.addListener(_onScroll);_loadGenres();_loadTrending();}
  void _onScroll(){if(_scroll.position.pixels>=_scroll.position.maxScrollExtent-700){_loadMore();}}
  Future<void> _loadMore() async {
    if(_loading||_loadingMore||!_hasMore)return;
    _loadingMore=true;final next=_page+1;
    try{
      final results=_search.text.trim().isNotEmpty
        ? await _tmdb.search(_search.text,page:next)
        : await _tmdb.discover(type:_apiType,genreId:_effectiveGenre,sortBy:_sort,minRating:_minRating==0?null:_minRating,page:next);
      if(!mounted)return;
      setState((){final seen=_items.map((e)=>e.id).toSet();_items.addAll(results.where((e)=>!seen.contains(e.id)));_page=next;_hasMore=results.isNotEmpty;});
    }catch(_){}finally{_loadingMore=false;}
  }
  @override void dispose(){_scroll.removeListener(_onScroll);_scroll.dispose();_search.dispose();super.dispose();}
  Future<void> _loadGenres() async {try{final r=await _tmdb.genres(type:_apiType);if(mounted)setState(()=>_genres=r);}catch(_){}}
  Future<void> _loadTrending() async {
    setState(()=>_loading=true);_error=null;_page=1;_hasMore=true;
    try{
      final requests=<Future<List<MediaItem>>>[_tmdb.trending()];
      for(var page=1;page<=10;page++){
        requests.add(_tmdb.popular(type:'movie',page:page));
        requests.add(_tmdb.popular(type:'tv',page:page));
      }
      final groups=await Future.wait(requests);
      final unique=<String,MediaItem>{};for(final group in groups){for(final item in group){unique['${item.mediaType}:${item.id}']=item;}}
      if(mounted)setState(()=>{_items=unique.values.toList(),_page=10,_hasMore:true});
    }catch(_){if(mounted)setState(()=>_error='Не удалось загрузить каталог. Проверьте подключение к интернету и попробуйте обновить страницу.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _applyFilters() async {
    setState(()=>_loading=true);_error=null;
    try{final r=await _tmdb.discover(type:_apiType,genreId:_effectiveGenre,sortBy:_sort,minRating:_minRating==0?null:_minRating);if(mounted)setState((){_items=r;_page=1;_hasMore=r.isNotEmpty;});}
    catch(_){if(mounted)setState(()=>_error='Не удалось применить фильтры.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _searchMedia(String value) async {
    if(value.trim().isEmpty){_loadTrending();return;}setState(()=>_loading=true);_error=null;
    try{final r=await _tmdb.search(value);if(mounted)setState(()=>{_items=r,_page=1,_hasMore=r.isNotEmpty});}
    catch(_){if(mounted)setState(()=>_error='Ошибка поиска. Проверьте подключение к интернету.');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  Future<void> _open(MediaItem item) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>MediaDetailsScreen(item:item)));if(mounted)setState((){});}
  Future<void> _openPage(Widget page) async {await Navigator.push(context,MaterialPageRoute(builder:(_)=>page));if(mounted)setState((){});}
  @override Widget build(BuildContext context){
    final profile=widget.profileService.activeProfile;
    return Scaffold(appBar:AppBar(title:const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('KinoKino',style:TextStyle(fontWeight:FontWeight.bold)),Text('by Osirisvectory',style:TextStyle(fontSize:10,color:Colors.white60))]),
      actions:[if(profile!=null)Padding(padding:const EdgeInsets.only(right:6),child:Center(child:Text(profile.name,style:const TextStyle(color:Colors.white70)))),
        PopupMenuButton<String>(onSelected:(v){if(v=='profiles')_openPage(ProfilesScreen(service:widget.profileService));if(v=='library')_openPage(const LibraryScreen());if(v=='settings')_openPage(SettingsScreen(service:widget.settingsService));if(v=='about')_openPage(const AboutScreen());if(v=='logout')AuthService().signOut();},
          itemBuilder:(_)=>const[PopupMenuItem(value:'profiles',child:ListTile(leading:Icon(Icons.people),title:Text('Профили'))),PopupMenuItem(value:'library',child:ListTile(leading:Icon(Icons.video_library),title:Text('Библиотека'))),PopupMenuItem(value:'settings',child:ListTile(leading:Icon(Icons.settings),title:Text('Настройки'))),PopupMenuItem(value:'about',child:ListTile(leading:Icon(Icons.info_outline),title:Text('О приложении'))),PopupMenuItem(value:'logout',child:ListTile(leading:Icon(Icons.logout),title:Text('Выйти из аккаунта')))])]),
      body:Column(children:[
        Padding(padding:const EdgeInsets.fromLTRB(16,8,16,10),child:TextField(controller:_search,onSubmitted:_searchMedia,decoration:InputDecoration(hintText:'Поиск фильмов, сериалов и мультфильмов',prefixIcon:const Icon(Icons.search),suffixIcon:IconButton(icon:const Icon(Icons.clear),onPressed:(){_search.clear();_loadTrending();})))),
        Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Column(children:[
          Row(children:[Expanded(child:SingleChildScrollView(scrollDirection:Axis.horizontal,child:SegmentedButton<String>(showSelectedIcon:false,segments:const[ButtonSegment(value:'movie',label:Text('Фильмы')),ButtonSegment(value:'tv',label:Text('Сериалы')),ButtonSegment(value:'animation',label:Text('Мультфильмы')),ButtonSegment(value:'animated_tv',label:Text('Мультсериалы'))],selected:{_type},onSelectionChanged:(v){setState(()=>{_type=v.first,_genreId=(v.first=='animation'||v.first=='animated_tv')?16:null});_loadGenres();_applyFilters();}))),
            const SizedBox(width:8),PopupMenuButton<String>(tooltip:'Сортировка',icon:const Icon(Icons.sort),onSelected:(v){setState(()=>_sort=v);_applyFilters();},itemBuilder:(_)=>const[PopupMenuItem(value:'popularity.desc',child:Text('Популярные')),PopupMenuItem(value:'vote_average.desc',child:Text('По рейтингу')),PopupMenuItem(value:'primary_release_date.desc',child:Text('Сначала новые')),PopupMenuItem(value:'revenue.desc',child:Text('По сборам'))])]),
          const SizedBox(height:8),Row(children:[
            Expanded(child:DropdownButtonFormField<int?>(value:_genreId,decoration:const InputDecoration(labelText:'Жанр',contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8)),items:[const DropdownMenuItem<int?>(value:null,child:Text('Все жанры')),..._genres.map((g)=>DropdownMenuItem<int?>(value:g['id'] as int,child:Text(g['name'].toString())))],onChanged:(v){setState(()=>_genreId=v);_applyFilters();})),
            const SizedBox(width:12),Expanded(child:DropdownButtonFormField<double>(value:_minRating,decoration:const InputDecoration(labelText:'Рейтинг от',contentPadding:EdgeInsets.symmetric(horizontal:12,vertical:8)),items:[0.0,5.0,6.0,7.0,8.0,9.0].map((v)=>DropdownMenuItem(value:v,child:Text(v==0?'Любой':'$v+'))).toList(),onChanged:(v){setState(()=>_minRating=v??0);_applyFilters();}))]),
        ])),
        const SizedBox(height:8),
        Expanded(child:_loading?const Center(child:CircularProgressIndicator()):_error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Column(mainAxisSize:MainAxisSize.min,children:[Text(_error!,textAlign:TextAlign.center),const SizedBox(height:12),FilledButton.icon(onPressed:_loadTrending,icon:const Icon(Icons.refresh),label:const Text('Повторить'))]))):_items.isEmpty?const Center(child:Text('Ничего не найдено.')):LayoutBuilder(builder:(context,c){
          final columns=c.maxWidth>1200?6:c.maxWidth>900?5:c.maxWidth>650?4:2;
          return GridView.builder(controller:_scroll,padding:const EdgeInsets.all(16),gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:columns,childAspectRatio:.58,crossAxisSpacing:14,mainAxisSpacing:16),itemCount:_items.length+(_hasMore?1:0),itemBuilder:(_,i)=>i>=_items.length?const Center(child:Padding(padding:EdgeInsets.all(20),child:CircularProgressIndicator())):PosterCard(item:_items[i],onTap:()=>_open(_items[i])));
        }))
      ]));
  }
}
