build:
	docker compose build

run:
	docker compose up -d

shell:
	docker compose exec app bash
