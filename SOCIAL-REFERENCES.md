# Ответы и группы: источники и ограничения

Оригинальные элементы GUI извлечены из предоставленного VK_2_0.ipa: left_answers, left_groups, group_placeholder_50px и обычные/Retina версии. Импорт и проверяемые SHA-256 записаны в tools/vk-ipa-assets.json. Для новых экранов также используются уже импортированные ProfileBlueButton, FooterButton, Navigation и кнопки возврата. Логотип VK не импортируется.

Найденные визуальные ориентиры:
- [Архив интерфейсов VK, раздел про приложение 2012 года](https://www.iphones.ru/iNotes/vk-ispolnilos-17-let--kak-menyalsya-dizayn-kazhdyy-god-i-chto-segodnya-tam-est-10-06-2023).
- [Скриншот старого профиля/ленты](https://cdn.iphones.ru/wp-content/uploads/2023/10/11-11-1241x725.jpg).
- [Скриншот сообщений/фотографий](https://cdn.iphones.ru/wp-content/uploads/2023/10/11-22-1241x725.jpg) — имеется и в папке Pictures/oldvk пользователя.
- [Обзор клиента эпохи iOS 6](https://lifehacker.ru/vkontakte2/amp/).

Это ориентиры эпохи, а не точные скриншоты новых экранов этого клиента. Поиск также находит VK App 2.0 с плоским дизайном iOS 7; он не используется для замены объёмных элементов.

Первичные источники API OpenVK:
- [groups.get](https://openvk.github.io/docs/openvk_engine/api/methods/groups/get/): список сообществ с count, offset, count и fields.
- [groups.getById](https://openvk.github.io/docs/openvk_engine/api/methods/groups/getById/): group_id, поля description, members_count, is_member и фотографии.
- [groups.search](https://openvk.github.io/docs/openvk_engine/api/methods/groups/search/): q, offset, count.
- [notifications.get](https://openvk.github.io/docs/openvk_engine/api/methods/notifications/get/): старый формат VK, count и offset.
- [notifications.markAsViewed](https://openvk.github.io/docs/openvk_engine/api/methods/notifications/markAsViewed/): отмечает все уведомления просмотренными; вызывается только кнопкой «Прочитано».

Уведомления загружаются внутри клиента; это не регистрация APNs и не push в фоне. Действия groups.join/leave выполняются только по нажатию пользователя, результат членства перечитывается с сервера. При отсутствии is_member кнопка подписки отключена. Неподдерживаемый метод и ошибки доступа показываются пользователю. Параметры join/leave и фактические ответы инстанса требуют проверки на живом сервере: сеть из среды разработки недоступна.

Для like_photo/like_comment ID объекта не используется как ID записи. Переход к записи разрешён только при явном post_id или подходящем типе родителя/события. При отсутствии адреса записи доступен переход к автору уведомления.
