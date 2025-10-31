# Mobus Motorista

> Aplicativo de monitoramento de ônibus voltado para motoristas, com compartilhamento e visualização de localização em tempo real. Esta versão é exclusiva para Android, enquanto a versão Web, destinada aos alunos/usuários, encontra-se separada e disponível no [Mobus Web](https://github.com/JairRodrigue/Mobus).

---

## Índice

- [Descrição Geral](#descrição-geral)
- [Recursos e Funcionalidades](#recursos-e-funcionalidades)
- [Dependências e Tecnologias](#dependências-e-tecnologias)
- [Instalação](#instalação)
- [Configuração do Ambiente (.env)](#configuração-do-ambiente-env)
- [Execução do Aplicativo](#execução-do-aplicativo)
- [Contribuição](#contribuição)
- [Licença](#licença)
- [Contato](#contato)
- [Links Relacionados](#links-relacionados)

---

## Descrição Geral

Mobus Motorista é um aplicativo Android desenvolvido em Flutter, voltado para motoristas de ônibus monitorarem e compartilharem sua localização em tempo real. Ele integra serviços de autenticação, mapa interativo e backend seguro, garantindo melhor planejamento e comunicação com passageiros.  
A versão Web destinada aos alunos pode ser acessada em: [Mobus Web](https://github.com/JairRodrigue/Mobus).

---

## Recursos e Funcionalidades

- Geolocalização em tempo real do veículo (motorista)
- Compartilhamento da localização ativa e dinâmica com passageiros/alunos
- Visualização em mapas interativos (OpenStreetMap)
- Autenticação segura via Firebase Authentication
- Backend conectado ao Firebase Realtime Database
- Sistema flexível para configuração via variáveis em arquivo `.env`
- Interface responsiva e adaptada exclusivamente para Android

---

## Dependências e Tecnologias

### Principais

- [Flutter](https://flutter.dev) (Android)
- [Firebase](https://firebase.google.com) (Realtime Database & Authentication)

### Bibliotecas utilizadas

- `flutter_dotenv: ^6.0.0`
- `firebase_core: ^2.27.0`
- `firebase_auth: ^4.17.0`
- `geolocator: ^12.0.0`
- `flutter_map: ^7.0.2`
- `latlong2: ^0.9.1`
- Outras dependências descritas em `pubspec.yaml`

---

## Instalação

### 1. Clonagem do Repositório
  ```
    git clone https://github.com/JairRodrigue/Mobus_Motorista
    
    cd Mobus_Motorista
  ```


### 2. Instalação das Dependências

  ```
    flutter pub get
  ```
---

## Configuração do Ambiente (.env)

Crie um arquivo `.env` na raiz do projeto contendo as credenciais e variáveis necessárias para inicialização dos serviços Firebase:

- `API_KEY=...` (Chave de API do Firebase)
- `AUTH_DOMAIN=...` (Domínio de autenticação Firebase)
- `PROJECT_ID=...` (ID do projeto Firebase)
- `STORAGE_BUCKET=...` (Bucket de armazenamento Firebase)
- `MESSAGING_SENDER_ID=...` (ID do remetente de mensagens Firebase)
- `APP_ID=...` (ID da aplicação Firebase)
- `MEASUREMENT_ID=...` (ID de medição do Google Analytics 4)
- `DATABASE_URL=...` (Link do Realtime Database do Firebase)

> **Atenção:** O arquivo `.env` contém informações confidenciais e não deve ser versionado ou compartilhado publicamente.

---

## Execução do Aplicativo

### Android (Mobile)

1. Verifique os emuladores disponíveis:
    ```
    flutter emulators
    ```
2. Inicie o emulador desejado:
    ```
    flutter emulators --launch <nome_do_emulador>
    ```
3. Execute o projeto:
    ```
    flutter run
    ```

---

## Contribuição

Contribuições, sugestões ou melhorias são bem-vindas! Para contribuir, siga os passos:

1. Realize fork do repositório
2. Crie uma branch específica para sua contribuição
3. Descreva claramente sua proposta no Pull Request

---

## Licença

Este projeto está sob a licença. Detalhes disponíveis em [`LICENSE`](LICENSE).

---

## Contato

**Equipe de Desenvolvimento**
- **Jair Rodrigues**  
  GitHub: [https://github.com/JairRodrigue](https://github.com/JairRodrigue)
- **Keila Roberta**  
  GitHub: [https://github.com/keilarobertasv](https://github.com/keilarobertasv)
- **Chaylane Franco**  
  GitHub: [https://github.com/Chayfranco](https://github.com/Chayfranco)

---

## Links Relacionados

- Versão Web para alunos: [github.com/JairRodrigue/Mobus](https://github.com/JairRodrigue/Mobus)
- Landing page do projeto: [mobusproject.netlify.app](https://mobusproject.netlify.app)