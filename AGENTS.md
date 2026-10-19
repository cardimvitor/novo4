# Regras para agentes neste repositório

Estas regras valem para Claude Code, Codex e DeepSeek (aider). Leia tudo antes de mexer no código.

## 1. Antes de começar: olhe o quadro

- O quadro fica em `.agents/tasks/`, um arquivo JSON por Issue (`issue-N.json`).
- Leia todos os arquivos ali. Se a Issue atual já tem status `in-progress` ou `pr-open`, não refaça o trabalho.
- Se outra tarefa aberta cobre o mesmo pedido ou os mesmos arquivos, não duplique: explique no seu resumo qual tarefa já cobre e pare.
- Não edite arquivos de `.agents/tasks/`. O quadro é atualizado pelos workflows.

## 2. Ao terminar: explique para o próximo agente

Todo PR precisa de uma explicação. Escreva em `.agents/handoffs/issue-N.md` (N é o número da Issue) com:

- **O que mudou**: frase curta por arquivo ou área.
- **Por que**: a decisão que foi tomada e a alternativa descartada, se houver.
- **O que ficou fora**: o que a Issue pedia e você não fez, e por quê.
- **Como testar**: comandos exatos que você rodou ou que o revisor deve rodar.
- **Pontos de atenção**: conflitos prováveis, arquivos sensíveis, dívidas.

Esse arquivo vira a seção "Para os outros agentes" do PR. Não deixe de escrevê-lo, mesmo quando a mudança for pequena.

## 3. Regras de código

- Mantenha a mudança no escopo da Issue. Não reformate arquivos alheios.
- Rode `npm run typecheck` antes de terminar quando mexer em TypeScript.
- Nunca coloque chaves, tokens ou secrets em arquivos, commits ou PRs.
- Não faça merge. Os PRs saem em rascunho para revisão humana.
