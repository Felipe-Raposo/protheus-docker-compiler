#!/bin/bash

set -o pipefail

export LC_ALL=C
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:.

# Descompacta o binário.
if [[ -f "/protheus12/bin/appserver.tar.xz" ]]; then
	cd /protheus12/bin/
	tar -xvf appserver.tar.xz
	rm appserver.tar.xz
fi

# Aplica patches que estão no diretório /patches.
if [[ -d "/patches" ]]; then
	cd /protheus12/bin/appserver || exit 1

	outreport="/patches/log"
	applied_dir="/patches/aplicadas"
	patch_errors_log="${outreport}/patch_errors.log"
	patch_count=0
	applied_patches=0
	failed_patches=0

	mkdir -p "$outreport" "$applied_dir"

	# Detecta se a saida e interativa (TTY) para decidir animar o spinner.
	if [[ -t 1 ]]; then interactive=1; else interactive=0; fi

	spinner_frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

	# Aguarda o processo em background exibindo o estado "Aplicando".
	# Em TTY, anima um spinner na mesma linha; caso contrario, imprime uma vez.
	wait_with_spinner() {
		local pid="$1" name="$2"
		local i=0 frame
		if [[ $interactive -eq 1 ]]; then
			while kill -0 "$pid" 2>/dev/null; do
				frame="${spinner_frames[i++ % ${#spinner_frames[@]}]}"
				printf '\r%s Patch %s\t\tAplicando' "$frame" "$name"
				sleep 0.1
			done
		else
			printf -- '- Patch %s\t\tAplicando\n' "$name"
		fi
		wait "$pid"
		return $?
	}

	# Imprime a linha final do patch (icone, nome, status e tempo).
	print_result() {
		local icon="$1" name="$2" status="$3" secs="$4"
		if [[ $interactive -eq 1 ]]; then
			printf '\r%s Patch %s\t\t%s - %ss\033[K\n' "$icon" "$name" "$status" "$secs"
		else
			printf '%s Patch %s\t\t%s - %ss\n' "$icon" "$name" "$status" "$secs"
		fi
	}

	shopt -s nullglob nocaseglob
	for patch in /patches/*.ptm; do
		patch_name=$(basename "$patch")
		patch_base="${patch_name%.*}"
		patch_log="${outreport}/${patch_base}.log"

		rm -f "$patch_errors_log"
		patch_start=$SECONDS
		./appsrvlinux -compile -applypatch -env="P12" -files="$patch" -outreport="$outreport" > "$patch_log" 2>&1 &
		cmd_pid=$!
		wait_with_spinner "$cmd_pid" "$patch_base"
		exit_code=$?
		elapsed=$((SECONDS - patch_start))

		if [[ $exit_code -eq 0 ]] && [[ ! -s "$patch_errors_log" ]]; then
			print_result "✔" "$patch_base" "Aplicada" "$elapsed"
			mv "$patch" "${applied_dir}/${patch_name}"
			mv "$patch_log" "${applied_dir}/${patch_base}.log"
			((applied_patches++))
		else
			print_result "✖" "$patch_base" "Falhou" "$elapsed"
			if [[ -s "$patch_errors_log" ]]; then
				mv "$patch_errors_log" "${outreport}/${patch_base}_patch_errors.log"
			fi
			((failed_patches++))
		fi

		((patch_count++))
		echo
	done
	shopt -u nullglob nocaseglob

	if [[ $patch_count -eq 0 ]]; then
		echo "Nenhuma patch (.ptm) encontrada em /patches."
	elif [[ $failed_patches -eq 0 ]] && [[ $patch_count -eq 1 ]]; then
		echo "Patch aplicado com sucesso."
	elif [[ $failed_patches -eq 0 ]]; then
		echo "Todas as ${patch_count} patch(es) foram aplicadas com sucesso."
	else
		if [[ $failed_patches -eq 1 ]]; then
			echo "****** Uma patch de ${patch_count} falhou ******"
		else
			echo "****** ${failed_patches} de ${patch_count} patch(es) falharam ******"
		fi
		echo "****** Verifique os arquivos de log na pasta ${outreport} para mais detalhes ******"
	fi

	if [[ $applied_patches -gt 0 ]]; then
		defrag_flag="$(echo "${PROTHEUS_DEFRAG_RPO:-TRUE}" | tr '[:lower:]' '[:upper:]')"
		case "$defrag_flag" in
			N|NO|0|FALSE|F)
				echo "Desfragmentacao do RPO ignorada (PROTHEUS_DEFRAG_RPO=${PROTHEUS_DEFRAG_RPO})."
				;;
			*)
				defrag_errors_log="${outreport}/defragrpo_errors.log"
				defrag_log="${outreport}/defragrpo.log"

				echo "Desfragmentando RPO..."

				rm -f "$defrag_errors_log"
				./appsrvlinux -compile -env="P12" -defragrpo -outreport="$outreport" > "$defrag_log" 2>&1
				defrag_exit_code=$?

				if [[ $defrag_exit_code -eq 0 ]] && [[ ! -s "$defrag_errors_log" ]]; then
					echo "RPO desfragmentado com sucesso."
				else
					echo "****** Erro ao desfragmentar RPO ******"
					echo "****** Verifique os arquivos de log na pasta ${outreport} para mais detalhes ******"
					exit 1
				fi
				;;
		esac
	fi

	if [[ $failed_patches -gt 0 ]]; then
		exit 1
	fi
fi
exit 0
