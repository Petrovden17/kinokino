import 'package:flutter/material.dart';
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('О KinoKino')),
    body:const Padding(padding:EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('KinoKino 1.0',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),
      SizedBox(height:8),Text('by Osirisvectory',style:TextStyle(fontSize:16,fontWeight:FontWeight.w600)),
      SizedBox(height:16),Text('Каталог использует TMDB для метаданных. TMDB не предоставляет сами фильмы или сериалы.'),
      SizedBox(height:12),Text('Воспроизведение предназначено только для видеоисточников, на которые у пользователя есть права или разрешение.'),
      SizedBox(height:12),Text('Chromecast, фоновые загрузки, системные уведомления и полноценные Android TV controls требуют отдельных платформенных интеграций и в этой сборке ещё не активированы.')
    ])));
}
