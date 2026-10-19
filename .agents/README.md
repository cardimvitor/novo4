# Quadro dos agentes

Cada Issue executada por um agente tem um arquivo em `tasks/issue-N.json`, criado e atualizado pelos workflows:

- `in-progress`: um agente começou. Outro agente não deve repetir a Issue.
- `pr-open`: o PR foi aberto. A explicação para os outros agentes está em `explanation`.

As regras de uso estão em `AGENTS.md`, na raiz do repositório.
